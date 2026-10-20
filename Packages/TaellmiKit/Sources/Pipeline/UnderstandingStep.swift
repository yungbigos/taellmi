import Config
import Domain
import Foundation
import Persistence

/// What the `understand` step needs (ADR 0012). Optional, so builds and tests without a language model run.
public struct UnderstandingWork: Sendable {
    let store: UnderstandingStore
    let prompts: PromptStore
    let models: any LanguageModelProvider

    public init(store: UnderstandingStore, prompts: PromptStore, models: any LanguageModelProvider) {
        self.store = store
        self.prompts = prompts
        self.models = models
    }

    /// The prompts and models in use, stored with every result; changing either makes all thoughts stale.
    func signature(_ resolver: ModelResolver) throws -> String {
        let concepts = "\(try prompts.current(role: .entities).ref)/\(try resolver.resolve(.entities).id)"
        let summary = "\(try prompts.current(role: .summary).ref)/\((try? resolver.resolve(.summary).id) ?? "none")"
        return concepts + "+" + summary
    }
}

extension PipelineRunner {
    /// Queues `understand` for thoughts whose concepts and summary are missing or out of date, but only while
    /// the model can run, so nothing piles up as failures while Apple Intelligence is off.
    func scheduleUnderstanding() async throws {
        guard let understanding, try pipeline.enabledSteps().contains(where: { $0.step == MeaningSteps.understand }),
            let model = try? resolver.resolve(.entities),
            let language = try? await understanding.models.languageModel(model),
            await language.availability() == .available
        else { return }
        let now = now()
        for entryID in try understanding.store.staleEntryIDs(promptRefs: try understanding.signature(resolver)) {
            try jobs.requeue(entryID: entryID, steps: [MeaningSteps.understand], now: now)
        }
        try understanding.store.pruneConcepts()
    }

    func understand(entryID: String) async throws {
        guard let understanding else { return }
        guard let entry = try index.entry(id: entryID) else { throw PipelineError.entryMissing(entryID) }
        let text = entry.text
        let signature = try understanding.signature(resolver)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Nothing to understand; stored as done, so it isn't queued again on every sweep.
            try understanding.store.replace(
                entryID: entryID, sourceText: text, understanding: Understanding(summary: nil, mentions: []),
                provenance: UnderstandingProvenance(modelID: "none", promptRefs: signature), now: now())
            return
        }
        // Concepts hang off passages; until the current Text is split, wait (the sweep queues it again).
        guard try !fragments.fragments(entryID: entryID).isEmpty else { return }

        let conceptModel = try resolver.resolve(.entities)
        let conceptPrompt = try understanding.prompts.current(role: .entities)
        let language = try await understanding.models.languageModel(conceptModel)
        let answer = try await language.generate(
            prompt: conceptPrompt.render(["text": text]), schema: conceptPrompt.outputSchema ?? .object([:]))
        let mentions = ConceptMentions.locate(
            in: text, answer: answer, kinds: try understanding.store.conceptKinds())

        var summary: String?
        let words = text.split(whereSeparator: \.isWhitespace).count
        if words >= Int(try settings.number(SettingKeys.summaryMinWords)) {
            let summaryModel = try resolver.resolve(.summary)
            let summaryPrompt = try understanding.prompts.current(role: .summary)
            do {
                let result = try await understanding.models.languageModel(summaryModel).generate(
                    prompt: summaryPrompt.render(["text": text]), schema: summaryPrompt.outputSchema ?? .object([:]))
                summary = result.objectValue?["summary"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if summary?.isEmpty == true { summary = nil }
            } catch LanguageModelError.unavailable(let reason) {
                throw LanguageModelError.unavailable(reason)
            } catch {
                // Too long, or the model declined (e.g. a sensitive topic): keep the concepts, skip the summary.
                logger.info("No summary for an Entry: \(String(describing: error))")
                summary = nil
            }
        }
        // The Text may have changed while the model was thinking; store against what was read, so a newer
        // edit shows up as stale and is understood again.
        try understanding.store.replace(
            entryID: entryID, sourceText: text, understanding: Understanding(summary: summary, mentions: mentions),
            provenance: UnderstandingProvenance(modelID: conceptModel.id, promptRefs: signature),
            now: now())
    }
}
