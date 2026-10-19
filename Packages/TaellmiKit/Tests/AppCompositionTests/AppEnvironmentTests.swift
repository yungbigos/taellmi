import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@testable import AppComposition

@Suite("The assembled app")
struct AppEnvironmentTests {
    @Test("a recording left in the scratch folder by a crash becomes an Entry on the next start")
    func recoversScratchRecordings() async throws {
        let home = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let paths = AppPaths(root: home.url)
        try FileManager.default.createDirectory(at: paths.scratch, withIntermediateDirectories: true)
        try Data("orphaned audio".utf8).write(to: paths.scratch.appendingPathComponent("orphan.m4a"))
        let fake = FakeTranscriber()
        let environment = try AppEnvironment(
            paths: paths, engines: ["fake_engine": { _, _ in fake }], recorder: FakeRecorder(folder: scratch.url))
        _ = try seedFakeTranscription(environment.database, modelsRoot: paths.models)

        try await environment.start()
        await environment.waitForPipeline()

        let entries = try await environment.journal.recentEntries(limit: 5)
        #expect(entries.count == 1)
        #expect(entries.first?.text == FakeTranscriber.germanResult.text)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.scratch.path).isEmpty)
    }

    @Test("on start, a voice Entry in the Archive without Text is transcribed")
    func transcribesLeftoverEntries() async throws {
        let home = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let paths = AppPaths(root: home.url)
        let files = EntryFileStore(storage: PlainFolderStorage(root: paths.archive))
        let leftover = try files.createVoiceEntry(
            Recording(file: try scratch.makeAudioFile(), durationSeconds: 3.4, startedAt: sampleDate))
        let fake = FakeTranscriber()
        let environment = try AppEnvironment(
            paths: paths, engines: ["fake_engine": { _, _ in fake }], recorder: FakeRecorder(folder: scratch.url))
        _ = try seedFakeTranscription(environment.database, modelsRoot: paths.models)

        try await environment.start()
        await environment.waitForPipeline()

        #expect(try files.loadEntry(folder: leftover.folder).entry.text == FakeTranscriber.germanResult.text)
    }

    @Test("a typed or already transcribed Entry is not sent to transcription again")
    func leavesFinishedEntriesAlone() async throws {
        let home = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let paths = AppPaths(root: home.url)
        let files = EntryFileStore(storage: PlainFolderStorage(root: paths.archive))
        var done = try files.saveTranscript(
            germanTranscript,
            for: try files.createVoiceEntry(
                Recording(file: try scratch.makeAudioFile(), durationSeconds: 3.4, startedAt: sampleDate)))
        done.text = "Schon fertig und von mir bearbeitet."
        try files.saveText(done)
        let fake = FakeTranscriber()
        let environment = try AppEnvironment(
            paths: paths, engines: ["fake_engine": { _, _ in fake }], recorder: FakeRecorder(folder: scratch.url))
        _ = try seedFakeTranscription(environment.database, modelsRoot: paths.models)

        try await environment.start()
        await environment.waitForPipeline()

        #expect(await fake.transcribeCalls.isEmpty)
    }

    @Test("a recording goes all the way to a transcribed, indexed Entry on disk")
    func endToEnd() async throws {
        let home = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let fake = FakeTranscriber()
        let paths = AppPaths(root: home.url)
        let environment = try AppEnvironment(
            paths: paths, engines: ["fake_engine": { _, _ in fake }],
            recorder: FakeRecorder(folder: scratch.url))
        _ = try seedFakeTranscription(environment.database, modelsRoot: paths.models)
        try await environment.start()

        let entry = try await environment.journal.addVoiceEntry(
            Recording(file: try scratch.makeAudioFile(), durationSeconds: 3.4, startedAt: sampleDate))
        await environment.waitForPipeline()

        let stored = try #require(try await environment.journal.recentEntries(limit: 5).first)
        #expect(stored.id == entry.id)
        #expect(stored.text == FakeTranscriber.germanResult.text)
        let markdown = try String(
            contentsOf: paths.archive.appendingPathComponent(entry.folder).appendingPathComponent("entry.md"),
            encoding: .utf8)
        #expect(markdown.contains("Ich war heute im Büro."))
    }

    @Test("rebuilding from the Archive restores the index after the database is lost")
    func rebuildsAfterDatabaseLoss() async throws {
        let home = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let paths = AppPaths(root: home.url)
        let fake = FakeTranscriber()
        do {
            let environment = try AppEnvironment(
                paths: paths, engines: ["fake_engine": { _, _ in fake }], recorder: FakeRecorder(folder: scratch.url))
            _ = try seedFakeTranscription(environment.database, modelsRoot: paths.models)
            try await environment.start()
            _ = try await environment.journal.addVoiceEntry(
                Recording(file: try scratch.makeAudioFile(), durationSeconds: 3.4, startedAt: sampleDate))
            await environment.waitForPipeline()
        }
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: paths.database.path + suffix)
        }

        let fresh = try AppEnvironment(
            paths: paths, engines: ["fake_engine": { _, _ in fake }], recorder: FakeRecorder(folder: scratch.url))
        try await fresh.start()
        #expect(try await fresh.journal.recentEntries(limit: 5).first?.text == FakeTranscriber.germanResult.text)
    }
}
