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
        let runner: PipelineRunner
        let jobs: JobQueue
        let clock = ManualDate()
        let model: ModelConfig

        init(fake: FakeTranscriber = FakeTranscriber()) throws {
            database = try makeDatabase()
            archive = try TemporaryDirectory()
            models = try TemporaryDirectory()
            files = EntryFileStore(storage: PlainFolderStorage(root: archive.url), calendar: berlinCalendar)
            index = EntryIndex(database: database)
            self.fake = fake
            model = try seedFakeTranscription(database, modelsRoot: models.url)
            let installation = ModelInstallation(root: models.url)
            let engines = EngineCache(
                factories: ["fake_engine": { _, _ in fake }], installation: installation, clock: TestClock(),
                idleUnload: { .seconds(60) })
            let resolver = ModelResolver(
                database: database, registeredEngines: ["fake_engine"], installation: installation,
                conditions: { RuntimeConditions(onBattery: false) })
            jobs = JobQueue(database: database)
            runner = PipelineRunner(
                jobs: jobs, files: files, index: index, resolver: resolver, engines: engines,
                settings: SettingsStore(database: database), pipeline: PipelineConfig(database: database),
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
                suffix: "a1b2")
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
        #expect(try harness.jobs.jobs(entryID: entry.id).map(\.step) == ["transcribe"])
        #expect(try harness.jobs.jobs(entryID: entry.id).map(\.state) == [.pending])
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
        #expect(try harness.jobs.jobs(entryID: entry.id).map(\.state) == [.done])
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

        #expect(try harness.jobs.jobs(entryID: entry.id).map(\.state) == [.done])
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
}
