import Clocks
import Config
import Domain
import Foundation
import GRDB
import Persistence
import Pipeline
import TestSupport
import Testing

@Suite("Processing pipeline")
struct PipelineRunnerTests {
    struct Harness {
        let database: AppDatabase
        let archive: TemporaryDirectory
        let models: TemporaryDirectory
        let files: EntryFileStore
        let index: EntryIndex
        let fake: FakeTranscriber
        let embedder: FakeEmbedder
        let fragments: FragmentStore
        let vectors: VectorStore
        let runner: PipelineRunner
        let engines: EngineCache<TestClock<Duration>>
        let jobs: JobQueue
        let clock = ManualDate()
        let model: ModelConfig
        let understandings: UnderstandingStore

        init(
            fake: FakeTranscriber = FakeTranscriber(), embedder: FakeEmbedder = FakeEmbedder(),
            vocabulary: [any VocabularySource] = [], names: Set<String> = [],
            languageModel: FakeLanguageModel? = nil
        ) throws {
            database = try makeDatabase()
            archive = try TemporaryDirectory()
            models = try TemporaryDirectory()
            files = EntryFileStore(storage: PlainFolderStorage(root: archive.url), calendar: berlinCalendar)
            index = EntryIndex(database: database)
            self.fake = fake
            self.embedder = embedder
            fragments = FragmentStore(database: database)
            vectors = VectorStore(database: database)
            model = try seedFakeTranscription(
                database, modelsRoot: models.url, languageModel: languageModel != nil)
            understandings = UnderstandingStore(database: database)
            let installation = ModelInstallation(root: models.url)
            let engines = EngineCache(
                factories: ["fake_engine": { _, _ in fake }], embedders: ["fake_embedder": { _, _ in embedder }],
                installation: installation, clock: TestClock(), idleUnload: { .seconds(60) })
            self.engines = engines
            let resolver = ModelResolver(
                database: database,
                registeredEngines: engines.registeredEngines.union(languageModel?.registeredEngines ?? []),
                installation: installation,
                conditions: { RuntimeConditions(onBattery: false) })
            jobs = JobQueue(database: database)
            runner = PipelineRunner(
                jobs: jobs, files: files, index: index, fragments: fragments, vectors: vectors, resolver: resolver,
                engines: engines, embedders: engines,
                settings: SettingsStore(database: database), pipeline: PipelineConfig(database: database),
                vocabulary: vocabulary, classifier: FakeWordClassifier(names: names),
                understanding: languageModel.map { [understandings, database] in
                    UnderstandingWork(store: understandings, prompts: PromptStore(database: database), models: $0)
                },
                now: { [clock] in clock.now() })
        }

        /// Runs the queue repeatedly, moving time forward past any backoff, until nothing is left.
        func runUntilSettled() async {
            for _ in 0..<10 {
                await runner.runPending()
                clock.advance(by: 3600)
            }
        }

        func addEntry() throws -> Entry {
            let entry = try files.createVoiceEntry(
                Recording(file: try archive.makeAudioFile(), durationSeconds: 3.4, startedAt: sampleDate),
                id: "a1b2")
            try index.upsert(entry, transcript: nil)
            return entry
        }
    }

    @Test("a new entry gets one pending job per enabled step, once")
    func enqueue() async throws {
        let harness = try Harness()
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)
        try await harness.runner.enqueue(entry)
        #expect(
            try harness.jobs.jobs(entryID: entry.id).map(\.step) == ["transcribe", "fragment", "embed", "understand"])
        #expect(try harness.jobs.jobs(entryID: entry.id).map(\.state) == [.pending, .pending, .pending, .pending])
    }

    @Test("running the queue transcribes the entry with the configured model and indexes it")
    func transcribes() async throws {
        let harness = try Harness()
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)

        await harness.runner.runPending()

        let indexed = try #require(try harness.index.entry(id: entry.id))
        #expect(indexed.transcriptModelID == "fake-transcriber")
        #expect(indexed.text == FakeTranscriber.germanResult.text)
        #expect(
            try harness.index.segments(entryID: entry.id).map(\.text) == [
                "Ich war heute im Büro.", "Honestly, ziemlich anstrengend.",
            ])
        #expect(try harness.files.loadEntry(folder: entry.folder).transcript?.text == FakeTranscriber.germanResult.text)
        #expect(try harness.jobs.jobs(entryID: entry.id).map(\.state) == [.done, .done, .done, .done])
    }

    @Test("a failing step is retried and succeeds within the attempt limit")
    func retries() async throws {
        let harness = try Harness(fake: FakeTranscriber(failTimes: 2))
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)
        await harness.runUntilSettled()
        let job = try #require(try harness.jobs.jobs(entryID: entry.id).first)
        #expect(job.state == .done)
        #expect(job.attempts == 3)
    }

    @Test("a step that keeps failing is marked failed with the reason")
    func givesUp() async throws {
        let harness = try Harness(fake: FakeTranscriber(failTimes: 10))
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)
        await harness.runUntilSettled()
        let job = try #require(try harness.jobs.jobs(entryID: entry.id).first)
        #expect(job.state == .failed)
        #expect(job.attempts == 3)
        #expect(job.lastError?.isEmpty == false)
    }

    @Test("jobs interrupted by a crash are picked up again on next launch")
    func recoversInterrupted() async throws {
        let harness = try Harness()
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)
        try await harness.database.writer.write { db in try db.execute(sql: "UPDATE job SET state = 'running'") }

        try await harness.runner.recoverInterrupted()
        await harness.runner.runPending()

        #expect(try harness.jobs.jobs(entryID: entry.id).map(\.state) == [.done, .done, .done, .done])
    }

    static let kymResult = RawTranscription(
        text: "Heute mit Kym telefoniert.",
        tokens: [TimedToken(text: "▁Heute", start: 0, end: 0.4), TimedToken(text: ".", start: 1.9, end: 2)],
        durationSeconds: 2)

    @Test("a new Text is corrected towards the Vocabulary, the correction is recorded, the Transcript stays verbatim")
    func correctsTowardsVocabulary() async throws {
        let harness = try Harness(
            fake: FakeTranscriber(result: Self.kymResult), vocabulary: [FakeVocabularySource(["Kim"])],
            names: ["Kym"])
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)

        await harness.runner.runPending()

        let loaded = try harness.files.loadEntry(folder: entry.folder)
        #expect(loaded.entry.text == "Heute mit Kim telefoniert.")
        #expect(loaded.transcript?.text == "Heute mit Kym telefoniert.")
        #expect(loaded.corrections == [VocabularyCorrection(from: "Kym", to: "Kim")])
    }

    @Test("terms from all sources are combined, and a failing source does not block transcription")
    func combinesSourcesAndToleratesFailure() async throws {
        let harness = try Harness(
            fake: FakeTranscriber(result: Self.kymResult),
            vocabulary: [FakeVocabularySource([], fails: true), FakeVocabularySource(["Kim"])],
            names: ["Kym"])
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)

        await harness.runner.runPending()

        #expect(try harness.files.loadEntry(folder: entry.folder).entry.text == "Heute mit Kim telefoniert.")
    }

    @Test("a recording in which no words were heard is discarded completely")
    func discardsSilence() async throws {
        let silence = RawTranscription(text: "  ", tokens: [], durationSeconds: 3)
        let harness = try Harness(fake: FakeTranscriber(result: silence))
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)

        await harness.runner.runPending()

        #expect(try harness.files.allEntryFolders().isEmpty)
        #expect(try harness.files.trashedFolders().isEmpty, "nothing to keep, so not even the Trash")
        #expect(try harness.index.entry(id: entry.id) == nil)
    }

    @Test("a failed attempt waits for the backoff before it is retried")
    func backsOff() async throws {
        let harness = try Harness(fake: FakeTranscriber(failTimes: 1))
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)

        await harness.runner.runPending()
        #expect(try harness.jobs.jobs(entryID: entry.id).first?.state == .pending)
        #expect(await harness.fake.transcribeCalls.count == 1, "no immediate retry")

        harness.clock.advance(by: 3600)
        await harness.runner.runPending()
        #expect(try harness.jobs.jobs(entryID: entry.id).first?.state == .done)
    }

    @Test("without a usable model the job waits without using up attempts, then runs once the model is there")
    func waitsForModel() async throws {
        let harness = try Harness()
        try FileManager.default.removeItem(at: harness.models.url.appendingPathComponent(harness.model.id))
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)

        await harness.runUntilSettled()
        let waiting = try #require(try harness.jobs.jobs(entryID: entry.id).first)
        #expect(waiting.state == .pending)
        #expect(waiting.attempts == 0)
        #expect(waiting.lastError?.contains("not downloaded") == true)

        try ModelInstallation(root: harness.models.url).markVerified(harness.model)
        await harness.runUntilSettled()
        #expect(try harness.jobs.jobs(entryID: entry.id).first?.state == .done)
    }

    @Test("a job that crashed the app on every attempt is not retried forever")
    func crashLoopStops() async throws {
        let harness = try Harness()
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)
        try await harness.database.writer.write { db in
            try db.execute(sql: "UPDATE job SET state = 'running', attempts = 3")
        }

        try await harness.runner.recoverInterrupted()

        #expect(try harness.jobs.jobs(entryID: entry.id).first?.state == .failed)
    }
}

@Suite("Job queue ordering")
struct JobQueueTests {
    @Test("a later step of an Entry waits until the earlier step is done")
    func stepsRunInOrder() throws {
        let database = try makeDatabase()
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO entry (id, created_at, source, folder) VALUES ('e', '2026-10-19 18:34:12', 'voice', 'f')
                    """)
        }
        let jobs = JobQueue(database: database)
        try jobs.enqueue(entryID: "e", steps: ["first", "second"], now: sampleDate)

        let first = try #require(try jobs.claimNext(now: sampleDate))
        #expect(first.step == "first")
        #expect(try jobs.claimNext(now: sampleDate) == nil)

        try jobs.markDone(first, now: sampleDate)
        #expect(try jobs.claimNext(now: sampleDate)?.step == "second")
    }

    @Test("a new recording is transcribed before a backlog of slow later steps for older thoughts")
    func earlierStepsFirst() throws {
        let database = try makeSeededDatabase()
        try database.writer.write { db in
            for id in ["old1", "old2", "new"] {
                try db.execute(
                    sql:
                        "INSERT INTO entry (id, created_at, source, folder) VALUES (?, '2026-10-19 18:34:12', 'voice', ?)",
                    arguments: [id, id])
            }
        }
        let jobs = JobQueue(database: database)
        try jobs.enqueue(entryID: "old1", steps: ["understand"], now: sampleDate)
        try jobs.enqueue(entryID: "old2", steps: ["understand"], now: sampleDate)
        try jobs.enqueue(entryID: "new", steps: ["transcribe", "fragment"], now: sampleDate)

        let next = try #require(try jobs.claimNext(now: sampleDate))
        #expect(next.entryID == "new")
        #expect(next.step == "transcribe")
    }
}
