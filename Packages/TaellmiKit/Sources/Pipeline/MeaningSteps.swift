import Config
import Domain
import Foundation
import Persistence

/// Step names of the meaning layer, as used in `pipeline_step` rows.
enum MeaningSteps {
    static let fragment = "fragment"
    static let embed = "embed"
    static let understand = "understand"
}

/// How Text is split into passages right now. Its name is stored with every Entry's passages, so a changed
/// setting makes all Entries stale and they are split again.
struct PassageMethod {
    let splitter: PassageSplitter
    let name: String

    init(settings: SettingsStore) throws {
        splitter = PassageSplitter(
            targetLength: Int(try settings.number(SettingKeys.fragmentTargetLength)),
            maxLength: Int(try settings.number(SettingKeys.fragmentMaxLength)))
        name = "passage_splitter@1(target=\(splitter.targetLength),max=\(splitter.maxLength))"
    }
}

extension PipelineRunner {
    /// Finds Entries whose passages or vectors are missing or out of date, and queues the steps that fix
    /// them. This covers typed and edited thoughts, Entries from before these steps existed, a rebuilt
    /// database, a changed splitting setting and a swapped embedding model, all the same way. Each check is
    /// one indexed query, so it stays cheap for large Archives.
    func scheduleMeaningWork() throws {
        let enabled = Set(try pipeline.enabledSteps().map(\.step))
        let now = now()
        if enabled.contains(MeaningSteps.fragment) {
            let method = try PassageMethod(settings: settings)
            let steps = [MeaningSteps.fragment, MeaningSteps.embed].filter(enabled.contains)
            for entryID in try fragments.staleEntryIDs(method: method.name) {
                try jobs.requeue(entryID: entryID, steps: steps, now: now)
            }
        }
        if enabled.contains(MeaningSteps.embed), let model = try? resolver.resolve(.embed) {
            for entryID in try fragments.entryIDsWithFragmentsMissingVectors(space: model.vectorSpace) {
                try jobs.requeue(entryID: entryID, steps: [MeaningSteps.embed], now: now)
            }
        }
    }

    func fragment(entryID: String) throws {
        guard let entry = try index.entry(id: entryID) else { throw PipelineError.entryMissing(entryID) }
        let method = try PassageMethod(settings: settings)
        try fragments.replace(
            entryID: entryID, spans: method.splitter.passages(in: entry.text), sourceText: entry.text,
            method: method.name, now: now())
    }

    /// Embeds the Entry's passages that have no vector from the configured model yet.
    func embed(entryID: String) async throws {
        let model = try resolver.resolve(.embed)
        let all = try fragments.fragments(entryID: entryID)
        let done = try vectors.nodeIDs(space: model.vectorSpace, among: all.map(\.id))
        let todo = all.filter { !done.contains($0.id) }
        guard !todo.isEmpty else { return }
        let batchSize = max(1, Int(try settings.number(SettingKeys.embedBatchSize)))

        let embedder = try await embedders.acquireEmbedder(model)
        do {
            for start in stride(from: 0, to: todo.count, by: batchSize) {
                let batch = Array(todo[start..<min(start + batchSize, todo.count)])
                let vectors = try await embedder.embed(batch.map(\.text), purpose: .document)
                guard vectors.count == batch.count else {
                    throw PipelineError.embeddingCountMismatch(expected: batch.count, got: vectors.count)
                }
                try self.vectors.upsert(Array(zip(batch.map(\.id), vectors)), space: model.vectorSpace)
            }
            await embedders.release(model)
        } catch {
            await embedders.release(model)
            throw error
        }
    }
}
