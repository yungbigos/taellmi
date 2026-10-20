import Config
import Domain
import Foundation
import GRDB
import Persistence
import Pipeline
import TestSupport
import Testing

@Suite("Passages and embeddings in the pipeline")
struct MeaningPipelineTests {
    typealias Harness = PipelineRunnerTests.Harness

    private func addTypedEntry(_ harness: Harness, text: String) throws -> Entry {
        let entry = try harness.files.createTypedEntry(text: text, createdAt: sampleDate)
        try harness.index.upsert(entry, transcript: nil)
        return entry
    }

    @Test("a typed thought is split into passages and every passage is embedded as a document")
    func typedEntry() async throws {
        let harness = try Harness()
        let entry = try addTypedEntry(harness, text: "Heute war ich an der Isar.\n\nMorgen treffe ich Marleen.")

        await harness.runUntilSettled()

        let fragments = try harness.fragments.fragments(entryID: entry.id)
        #expect(fragments.map(\.text) == ["Heute war ich an der Isar.", "Morgen treffe ich Marleen."])
        #expect(await harness.embedder.embeddedTexts == fragments.map(\.text))
        #expect(try harness.vectors.nodeIDs(space: fakeEmbeddingModel.vectorSpace) == Set(fragments.map(\.id)))
    }

    @Test("after transcription the new Text is split and embedded")
    func voiceEntry() async throws {
        let harness = try Harness()
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)

        await harness.runUntilSettled()

        let fragments = try harness.fragments.fragments(entryID: entry.id)
        #expect(fragments.map(\.text).joined(separator: " ") == FakeTranscriber.germanResult.text)
        #expect(try harness.vectors.nodeIDs(space: fakeEmbeddingModel.vectorSpace).count == fragments.count)
    }

    @Test("editing the Text re-splits it and embeds only the passages that changed")
    func editedText() async throws {
        let harness = try Harness()
        var entry = try addTypedEntry(harness, text: "Bleibt gleich.\n\nWird geändert.")
        await harness.runUntilSettled()

        entry.text = "Bleibt gleich.\n\nIst jetzt anders."
        try harness.files.saveText(entry)
        try harness.index.upsert(entry, transcript: nil)
        await harness.runUntilSettled()

        #expect(
            try harness.fragments.fragments(entryID: entry.id).map(\.text) == ["Bleibt gleich.", "Ist jetzt anders."])
        #expect(await harness.embedder.embeddedTexts == ["Bleibt gleich.", "Wird geändert.", "Ist jetzt anders."])
        #expect(try harness.vectors.nodeIDs(space: fakeEmbeddingModel.vectorSpace).count == 2)
    }

    @Test("without an embedding model the passages are kept and embedding waits for the model")
    func waitsForEmbeddingModel() async throws {
        let harness = try Harness()
        try FileManager.default.removeItem(at: harness.models.url.appendingPathComponent(fakeEmbeddingModel.id))
        let entry = try addTypedEntry(harness, text: "Ein Gedanke ohne Modell.")

        await harness.runUntilSettled()

        #expect(try harness.fragments.fragments(entryID: entry.id).count == 1)
        let embed = try #require(try harness.jobs.jobs(entryID: entry.id).first { $0.step == "embed" })
        #expect(embed.state == .pending)
        #expect(embed.attempts == 0)

        try ModelInstallation(root: harness.models.url).markVerified(fakeEmbeddingModel)
        await harness.runUntilSettled()
        #expect(try harness.vectors.nodeIDs(space: fakeEmbeddingModel.vectorSpace).count == 1)
    }

    @Test("a different splitting setting re-splits every Entry")
    func settingChangeResplits() async throws {
        let harness = try Harness()
        let entry = try addTypedEntry(
            harness, text: "Ein erster längerer Satz über den Tag. Ein zweiter längerer Satz über den Abend.")
        await harness.runUntilSettled()
        #expect(try harness.fragments.fragments(entryID: entry.id).count == 1)

        let editor = ConfigEditor(database: harness.database)
        try editor.setSetting(SettingKeys.fragmentTargetLength, to: .number(40))
        try editor.setSetting(SettingKeys.fragmentMaxLength, to: .number(60))
        await harness.runUntilSettled()

        #expect(try harness.fragments.fragments(entryID: entry.id).count == 2)
    }

    @Test("vectors of a deleted Entry are removed")
    func prunesDeleted() async throws {
        let harness = try Harness()
        let entry = try addTypedEntry(harness, text: "Kommt gleich in den Papierkorb.")
        await harness.runUntilSettled()
        try harness.index.remove(id: entry.id)

        await harness.runUntilSettled()

        #expect(try harness.vectors.nodeIDs(space: fakeEmbeddingModel.vectorSpace).isEmpty)
    }
}

extension MeaningPipelineTests {
    @Test("while another model is busy, a job waits without using up an attempt")
    func busyModelWaits() async throws {
        let harness = try Harness()
        let entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)
        _ = try await harness.engines.acquireEmbedder(fakeEmbeddingModel)

        await harness.runner.runPending()
        let waiting = try #require(try harness.jobs.jobs(entryID: entry.id).first)
        #expect(waiting.state == .pending)
        #expect(waiting.attempts == 0)

        await harness.engines.release(fakeEmbeddingModel)
        await harness.runUntilSettled()
        #expect(try harness.jobs.jobs(entryID: entry.id).map(\.state) == [.done, .done, .done])
    }

    @Test("a different vector size for the same model embeds every passage again")
    func sizeChangeReembeds() async throws {
        let harness = try Harness()
        let entry = try addTypedEntry(harness, text: "Ein Gedanke.")
        await harness.runUntilSettled()
        try await harness.database.writer.write { db in
            try db.execute(sql: "UPDATE model SET params_json = '{\"dimensions\": 64}' WHERE id = 'fake-embedder'")
        }

        await harness.runUntilSettled()

        let model = try ModelResolver(
            database: harness.database, registeredEngines: harness.engines.registeredEngines,
            installation: ModelInstallation(root: harness.models.url),
            conditions: { RuntimeConditions(onBattery: false) }
        ).resolve(.embed)
        #expect(model.vectorSpace != fakeEmbeddingModel.vectorSpace)
        #expect(try harness.vectors.nodeIDs(space: model.vectorSpace).count == 1)
        #expect(await harness.embedder.embeddedTexts == ["Ein Gedanke.", "Ein Gedanke."])
        withExtendedLifetime(entry) {}
    }

    @Test("a recording whose transcription failed is still split once you write its Text")
    func failedEarlierStep() async throws {
        let harness = try Harness(fake: FakeTranscriber(failTimes: 99))
        var entry = try harness.addEntry()
        try await harness.runner.enqueue(entry)
        await harness.runUntilSettled()
        #expect(try harness.jobs.jobs(entryID: entry.id).first?.state == .failed)

        entry.text = "Selbst aufgeschrieben."
        try harness.files.saveText(entry)
        try harness.index.upsert(entry, transcript: nil)
        await harness.runUntilSettled()

        #expect(try harness.fragments.fragments(entryID: entry.id).map(\.text) == ["Selbst aufgeschrieben."])
    }

    @Test("a thought taken out of the index and put back keeps its vectors")
    func restoreKeepsVectors() async throws {
        let harness = try Harness()
        let entry = try addTypedEntry(harness, text: "Kommt zurück.")
        await harness.runUntilSettled()

        try harness.index.remove(id: entry.id)
        try harness.index.upsert(entry, transcript: nil)
        await harness.runUntilSettled()

        #expect(try harness.vectors.nodeIDs(space: fakeEmbeddingModel.vectorSpace).count == 1)
        #expect(await harness.embedder.embeddedTexts == ["Kommt zurück."])
    }
}

@Suite("Requeueing work")
struct JobRequeueTests {
    @Test("requeueing makes finished steps pending again and adds missing ones, but leaves running and failed jobs")
    func requeue() throws {
        let database = try makeDatabase()
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO entry (id, created_at, source, folder) VALUES ('e', '2026-10-19 18:34:12', 'typed', 'f')
                    """)
        }
        let jobs = JobQueue(database: database)
        try jobs.enqueue(entryID: "e", steps: ["done", "running", "failed"], now: sampleDate)
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE job SET state = step, attempts = 3;
                    """)
        }

        try jobs.requeue(entryID: "e", steps: ["done", "running", "failed", "new"], now: sampleDate)

        let byStep = Dictionary(uniqueKeysWithValues: try jobs.jobs(entryID: "e").map { ($0.step, $0) })
        #expect(byStep["done"]?.state == .pending)
        #expect(byStep["done"]?.attempts == 0)
        #expect(byStep["running"]?.state == .running)
        #expect(byStep["failed"]?.state == .failed)
        #expect(byStep["new"]?.state == .pending)
    }
}
