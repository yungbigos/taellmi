import Config
import Domain
import Foundation
import Persistence
import os

/// Runs queued work for entries, one job at a time, using whatever models the config assigns.
public actor PipelineRunner {
    private let logger = Logger(subsystem: "app.taellmi", category: "pipeline")
    private let jobs: JobQueue
    private let files: EntryFileStore
    private let index: EntryIndex
    private let resolver: ModelResolver
    private let engines: any TranscriberProvider
    private let settings: SettingsStore
    private let pipeline: PipelineConfig
    private let vocabulary: [any VocabularySource]
    private let classifier: any WordClassifier
    private let now: @Sendable () -> Date
    private var isRunning = false

    public init(
        jobs: JobQueue, files: EntryFileStore, index: EntryIndex, resolver: ModelResolver,
        engines: any TranscriberProvider, settings: SettingsStore, pipeline: PipelineConfig,
        vocabulary: [any VocabularySource], classifier: any WordClassifier,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.vocabulary = vocabulary
        self.classifier = classifier
        self.now = now
        self.jobs = jobs
        self.files = files
        self.index = index
        self.resolver = resolver
        self.engines = engines
        self.settings = settings
        self.pipeline = pipeline
    }

    public func enqueue(_ entry: Entry) throws {
        try jobs.enqueue(entryID: entry.id, steps: pipeline.enabledSteps().map(\.step))
    }

    public func recoverInterrupted() throws {
        try jobs.recoverInterrupted(maxAttempts: RetryPolicy(settings: settings).maxAttempts)
    }

    /// Works through the queue until nothing runnable is left. Safe to call repeatedly.
    public func runPending() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        while true {
            let policy: RetryPolicy
            let job: Job
            do {
                policy = try RetryPolicy(settings: settings)
                guard let next = try jobs.claimNext(now: now()) else { return }
                job = next
            } catch {
                logger.error("Pipeline paused, config or queue unreadable: \(String(describing: error))")
                return
            }
            await process(job, policy: policy)
        }
    }

    private func process(_ job: Job, policy: RetryPolicy) async {
        do {
            switch job.step {
            case "transcribe": try await transcribe(entryID: job.entryID)
            default: throw PipelineError.unknownStep(job.step)
            }
            try jobs.markDone(job, now: now())
        } catch let error as ResolutionError {
            logger.info("Step \(job.step) waits for a model: \(error.description)")
            try? jobs.markWaiting(job, reason: error.description, retryAfter: policy.waitForModel, now: now())
        } catch {
            logger.error("Step \(job.step) failed (attempt \(job.attempts)): \(String(describing: error))")
            try? jobs.markFailed(
                job, error: String(describing: error), maxAttempts: policy.maxAttempts, backoff: policy.backoff,
                now: now())
        }
    }

    private func transcribe(entryID: String) async throws {
        guard let entry = try index.entry(id: entryID) else { throw PipelineError.entryMissing(entryID) }
        let model = try resolver.resolve(.transcription)
        let audio = try files.recordingURL(for: entry)

        let transcriber = try await engines.acquire(model)
        let raw: RawTranscription
        do {
            raw = try await transcriber.transcribe(audioFile: audio)
            await engines.release(model)
        } catch {
            await engines.release(model)
            throw error
        }

        let maxPause = try settings.number(SettingKeys.segmentMaxPauseSeconds)
        let transcript = Transcript(
            text: raw.text, segments: SegmentBuilder(maxPause: maxPause).segments(from: raw.tokens),
            modelID: model.id, durationSeconds: raw.durationSeconds)
        let corrected = try await correctTowardsVocabulary(transcript.text)
        let updated = try files.saveTranscript(
            transcript, for: entry, firstText: corrected.text, corrections: corrected.corrections)
        try index.upsert(updated, transcript: transcript)
    }

    /// Corrects names in a new Text. A failing Vocabulary source is skipped, never fatal.
    private func correctTowardsVocabulary(_ text: String) async throws -> VocabularyCorrector.Result {
        var terms: [VocabularyTerm] = []
        for source in vocabulary {
            do {
                terms += try await source.terms()
            } catch {
                logger.error("A Vocabulary source failed: \(String(describing: error))")
            }
        }
        let corrector = VocabularyCorrector(
            terms: terms, minSimilarityForNames: try settings.number(SettingKeys.vocabularyMinSimilarityNames),
            minSimilarityOtherWords: try settings.number(SettingKeys.vocabularyMinSimilarityOther))
        return corrector.correct(text, using: classifier)
    }
}

/// Retry settings, read fresh from config for every job.
struct RetryPolicy {
    var maxAttempts: Int
    var backoff: TimeInterval
    var waitForModel: TimeInterval

    init(settings: SettingsStore) throws {
        maxAttempts = Int(try settings.number(SettingKeys.maxJobAttempts))
        backoff = try settings.number(SettingKeys.retryBackoffSeconds)
        waitForModel = try settings.number(SettingKeys.waitForModelSeconds)
    }
}

public enum PipelineError: Error, Equatable {
    case unknownStep(String)
    case entryMissing(String)
}
