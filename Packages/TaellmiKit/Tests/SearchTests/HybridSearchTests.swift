import Config
import Domain
import Foundation
import Persistence
import Search
import TestSupport
import Testing

@Suite("Search by words and meaning")
struct HybridSearchTests {
    struct Harness {
        let database: AppDatabase
        let models: TemporaryDirectory
        let index: EntryIndex
        let provider = FakeEmbedderProvider()
        let search: HybridSearch

        init() throws {
            database = try makeDatabase()
            models = try TemporaryDirectory()
            _ = try seedFakeTranscription(database, modelsRoot: models.url)
            index = EntryIndex(database: database)
            let installation = ModelInstallation(root: models.url)
            search = HybridSearch(
                index: index, fragments: FragmentStore(database: database), vectors: VectorStore(database: database),
                resolver: ModelResolver(
                    database: database, registeredEngines: ["fake_engine", "fake_embedder"],
                    installation: installation, conditions: { RuntimeConditions(onBattery: false) }),
                embedders: provider, settings: SettingsStore(database: database))
            try ConfigEditor(database: database).setSetting(SettingKeys.searchMinSimilarity, to: .number(0.3))
        }

        /// Indexes a thought with one passage per paragraph, embedded by the fake model.
        func add(_ id: String, _ text: String, daysAgo: Double = 0, source: EntrySource = .typed) throws {
            let entry = Entry(
                id: id, createdAt: sampleDate.addingTimeInterval(-daysAgo * 86_400), durationSeconds: nil,
                source: source, folder: id, text: text)
            try index.upsert(entry, transcript: nil)
            let spans = PassageSplitter(targetLength: 600, maxLength: 1200).passages(in: text)
            let stored = try FragmentStore(database: database).replace(
                entryID: id, spans: spans, sourceText: "test", method: "test@1")
            try VectorStore(database: database).upsert(
                stored.map { ($0.id, FakeEmbedder.vector($0.text)) }, space: fakeEmbeddingModel.vectorSpace)
        }

        func ids(_ text: String, period: EntryQuery.Period = .all, sources: Set<EntrySource>? = nil) async throws
            -> [String]
        {
            try await search.search(EntryQuery(text: text, period: period, sources: sources), now: sampleDate)
                .map(\.id)
        }
    }

    @Test("with no search words, thoughts stay newest first")
    func emptyQuery() async throws {
        let harness = try Harness()
        try harness.add("old", "Alter Gedanke.", daysAgo: 2)
        try harness.add("new", "Neuer Gedanke.")
        #expect(try await harness.ids("") == ["new", "old"])
        #expect(await harness.provider.embedder.calls.isEmpty, "no model needed without search words")
    }

    @Test("a thought that matches only by meaning is found")
    func meaningOnly() async throws {
        let harness = try Harness()
        try harness.add("worry", "Ich habe Angst vor der Zukunft.")
        try harness.add("bike", "Fahrrad repariert, Kette geölt.")
        #expect(try await harness.ids("Zukunftsangst") == ["worry"])
    }

    @Test("the search text is embedded as a query, and the model is handed back")
    func embedsAsQuery() async throws {
        let harness = try Harness()
        try harness.add("a", "Etwas.")
        _ = try await harness.ids("Zukunftsangst")
        let calls = await harness.provider.embedder.calls
        #expect(calls.map(\.texts) == [["Zukunftsangst"]])
        #expect(calls.map(\.purpose) == [.query])
        #expect(await harness.provider.released == 1)
    }

    @Test("the best match comes first, whatever its date")
    func bestMatchFirst() async throws {
        let harness = try Harness()
        try harness.add("strong", "Marleen hat angerufen. Marleen kommt am Wochenende.", daysAgo: 30)
        try harness.add("weak", "Viele Termine diese Woche, auch einer mit Marleen und dem ganzen Team im Büro.")
        #expect(try await harness.ids("Marleen") == ["strong", "weak"])
    }

    @Test("time and source filters apply to meaning matches too")
    func filters() async throws {
        let harness = try Harness()
        try harness.add("recent", "Angst vor der Zukunft, heute.")
        try harness.add("old", "Angst vor der Zukunft, letztes Jahr.", daysAgo: 400)
        try harness.add("spoken", "Angst vor der Zukunft, gesprochen.", source: .voice)
        #expect(try await harness.ids("Zukunftsangst", period: .month, sources: [.typed]) == ["recent"])
    }

    @Test("thoughts below the similarity threshold are not shown")
    func threshold() async throws {
        let harness = try Harness()
        try ConfigEditor(database: harness.database).setSetting(SettingKeys.searchMinSimilarity, to: .number(0.99))
        try harness.add("worry", "Ich habe Angst vor der Zukunft.")
        #expect(try await harness.ids("Zukunftsangst").isEmpty)
    }

    @Test("without a usable embedding model, search still finds words")
    func noModel() async throws {
        let harness = try Harness()
        try FileManager.default.removeItem(at: harness.models.url.appendingPathComponent(fakeEmbeddingModel.id))
        try harness.add("worry", "Ich habe Angst vor der Zukunft.")
        try harness.add("word", "Zukunftsangst ist ein langes Wort.")
        #expect(try await harness.ids("Zukunftsangst") == ["word"])
    }

    @Test("while another model is busy, search answers with words instead of waiting")
    func busyModel() async throws {
        let harness = try Harness()
        await harness.provider.setBusy(true)
        try harness.add("worry", "Ich habe Angst vor der Zukunft.")
        try harness.add("word", "Zukunftsangst ist ein langes Wort.")
        #expect(try await harness.ids("Zukunftsangst") == ["word"])
    }

    @Test("a thought found by both words and meaning ranks above those found by only one")
    func bothBeatsOne() async throws {
        let harness = try Harness()
        try harness.add("meaning", "Ich habe Angst vor der Zukunft.")
        try harness.add("both", "Zukunftsangst, immer wieder.", daysAgo: 10)
        try harness.add("words", "Zukunftsangstfreie Ferien: Strand, Eis, Sonne, Meer und Kinder im Sand.")
        #expect(try await harness.ids("Zukunftsangst").first == "both")
    }

    @Test("with a relative window, meaning matches far below the best one are dropped")
    func relativeWindow() async throws {
        let harness = try Harness()
        try ConfigEditor(database: harness.database).setSetting(SettingKeys.searchMinSimilarity, to: .number(0))
        try harness.add("close", "Zukunftsangst, immer wieder Zukunftsangst.")
        try harness.add("far", "Ich habe Angst vor der Zukunft.")
        #expect(Set(try await harness.ids("Zukunftsangst")) == ["close", "far"])

        try ConfigEditor(database: harness.database).setSetting(
            SettingKeys.searchRelativeSimilarityWindow, to: .number(0.05))
        #expect(try await harness.ids("Zukunftsangst") == ["close"])
    }

    @Test("thoughts with the search words come first; thoughts found only by meaning follow, marked as related")
    func wordsBeforeRelated() async throws {
        let harness = try Harness()
        try harness.add("related", "Zukunftsängste, Zukunftsängste, immer diese Zukunftsängste.")
        try harness.add("words", "Heute Zukunftsangst gehabt, dann Fahrrad repariert, Kette geölt, Reifen gewechselt.")
        let hits = try await harness.search.hits(EntryQuery(text: "Zukunftsangst"), now: sampleDate)
        #expect(hits.map(\.entry.id) == ["words", "related"])
        #expect(hits.map(\.match) == [.words, .related])
    }

    @Test("without words in common, every result is related")
    func onlyRelated() async throws {
        let harness = try Harness()
        try harness.add("worry", "Ich habe Angst vor der Zukunft.")
        let hits = try await harness.search.hits(EntryQuery(text: "Zukunftsangst"), now: sampleDate)
        #expect(hits.map(\.match) == [.related])
    }

    @Test("a result knows where its search words are, and a related thought knows the passage that matched")
    func matchPositions() async throws {
        let harness = try Harness()
        try harness.add("words", "Fahrrad repariert.\n\nDie Zukunftsangst kam abends wieder.")
        try harness.add("related", "Einkaufen war heute.\n\nIch habe Angst vor der Zukunft.")
        let hits = try await harness.search.hits(EntryQuery(text: "Zukunftsangst"), now: sampleDate)
        let words = try #require(hits.first { $0.entry.id == "words" })
        let units = Array(words.entry.text.utf16)
        #expect(words.wordRanges.map { String(decoding: units[$0], as: UTF16.self) } == ["Zukunftsangst"])
        #expect(words.passage == nil)

        let related = try #require(hits.first { $0.entry.id == "related" })
        let passage = try #require(related.passage)
        let relatedUnits = Array(related.entry.text.utf16)
        #expect(String(decoding: relatedUnits[passage], as: UTF16.self) == "Ich habe Angst vor der Zukunft.")
    }
}
