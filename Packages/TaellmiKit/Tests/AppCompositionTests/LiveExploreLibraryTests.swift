import Config
import Domain
import Features
import Foundation
import Persistence
import Search
import Synchronization
import TestSupport
import Testing

@testable import AppComposition

@Suite("Explore working on the real Archive")
struct LiveExploreLibraryTests {
    private func setUp(onChange: @escaping @Sendable () -> Void = {}) throws -> (
        LiveExploreLibrary, EntryFileStore, Entry, TemporaryDirectory
    ) {
        let (library, files, entry, temp, _) = try setUpWithDatabase(onChange: onChange)
        return (library, files, entry, temp)
    }

    private func setUpWithDatabase(onChange: @escaping @Sendable () -> Void = {}) throws -> (
        LiveExploreLibrary, EntryFileStore, Entry, TemporaryDirectory, AppDatabase
    ) {
        let temp = try TemporaryDirectory()
        let files = EntryFileStore(
            storage: PlainFolderStorage(root: temp.url, systemTrash: { try FileManager.default.removeItem(at: $0) }),
            calendar: berlinCalendar)
        let database = try makeDatabase()
        _ = try seedFakeTranscription(database, modelsRoot: temp.url.appendingPathComponent("models"))
        let index = EntryIndex(database: database)
        let search = HybridSearch(
            index: index, fragments: FragmentStore(database: database), vectors: VectorStore(database: database),
            resolver: ModelResolver(
                database: database, registeredEngines: ["fake_engine", "fake_embedder"],
                installation: ModelInstallation(root: temp.url.appendingPathComponent("models")),
                conditions: { RuntimeConditions(onBattery: false) }),
            embedders: FakeEmbedderProvider(), settings: SettingsStore(database: database))
        let entry = try files.saveTranscript(
            germanTranscript,
            for: try files.createVoiceEntry(
                Recording(file: try temp.makeAudioFile(), durationSeconds: 5.6, startedAt: sampleDate),
                id: "ex01"))
        try index.upsert(entry, transcript: germanTranscript)
        return (
            LiveExploreLibrary(files: files, index: index, search: search, onChange: onChange), files, entry, temp,
            database
        )
    }

    @Test("search finds a thought by meaning even without its exact words")
    func searchByMeaning() async throws {
        let (library, files, entry, temp, database) = try setUpWithDatabase()
        // The Entry's passages are embedded by the pipeline in the app; here they are stored directly.
        let fragments = try FragmentStore(database: database).replace(
            entryID: entry.id, spans: PassageSplitter(targetLength: 600, maxLength: 1200).passages(in: entry.text),
            sourceText: "test", method: "test@1")
        try VectorStore(database: database).upsert(
            fragments.map { ($0.id, FakeEmbedder.vector($0.text)) }, space: fakeEmbeddingModel.vectorSpace)
        try ConfigEditor(database: database).setSetting(SettingKeys.searchMinSimilarity, to: .number(0.3))

        #expect(try await library.search(EntryQuery(text: "Zukunftsängste")).map(\.id) == [entry.id])
        withExtendedLifetime((temp, files)) {}
    }

    @Test("writing or editing a thought asks for its passages to be refreshed")
    func editsTriggerRefresh() async throws {
        let calls = Mutex(0)
        let (library, _, entry, temp) = try setUp(onChange: { calls.withLock { $0 += 1 } })
        try await library.saveText(id: entry.id, text: "Neuer Gedanke.")
        _ = try await library.createThought(text: "Noch einer.")
        #expect(calls.withLock { $0 } == 2)
        withExtendedLifetime(temp) {}
    }

    @Test("the detail has the Text from disk, the Transcript segments and the recording")
    func detail() async throws {
        let (library, _, entry, temp) = try setUp()
        let detail = try await library.detail(id: entry.id)
        #expect(detail.entry.text == germanTranscript.text)
        #expect(detail.segments == germanTranscript.segments)
        #expect(detail.recordingURL?.lastPathComponent == "recording.m4a")
        withExtendedLifetime(temp) {}
    }

    @Test("an edit is written to entry.md and is found by search right away")
    func edit() async throws {
        let (library, files, entry, temp) = try setUp()
        try await library.saveText(id: entry.id, text: "Neuer Gedanke über Kaffee.")
        #expect(try files.loadEntry(folder: entry.folder).entry.text == "Neuer Gedanke über Kaffee.")
        #expect(try await library.search(EntryQuery(text: "kaffee")).map(\.id) == [entry.id])
        withExtendedLifetime(temp) {}
    }

    @Test("Trash, restore and delete for good")
    func trashCycle() async throws {
        let (library, _, entry, temp) = try setUp()
        let trashed = try await library.trash(id: entry.id)
        #expect(try await library.search(EntryQuery()).isEmpty)
        #expect(try await library.trashed().map(\.entry.id) == [entry.id])

        try await library.restore(trashedFolder: trashed)
        #expect(try await library.search(EntryQuery()).map(\.id) == [entry.id])

        let again = try await library.trash(id: entry.id)
        try await library.deleteForever(trashedFolder: again)
        #expect(try await library.trashed().isEmpty)
        withExtendedLifetime(temp) {}
    }

    @Test("a thought written in the composer becomes a typed Entry on disk and in the index")
    func createThought() async throws {
        let (library, files, _, temp) = try setUp()
        let created = try await library.createThought(text: "Ganz in Ruhe geschrieben.")
        #expect(created.source == .typed)
        #expect(try files.loadEntry(folder: created.folder).entry.text == "Ganz in Ruhe geschrieben.")
        #expect(try await library.search(EntryQuery(text: "ruhe")).map(\.id) == [created.id])
        withExtendedLifetime(temp) {}
    }

    @Test("changing a thought's date writes it to entry.md and the index, and keeps its Text")
    func changeDate() async throws {
        let (library, files, entry, temp) = try setUp()
        let written = sampleDate.addingTimeInterval(-86_400 * 200)

        try await library.setDate(id: entry.id, to: written)

        #expect(try files.loadEntry(folder: entry.folder).entry.createdAt == written)
        #expect(try files.loadEntry(folder: entry.folder).entry.text == entry.text)
        #expect(try await library.detail(id: entry.id).entry.createdAt == written)
        let listed = try await library.search(EntryQuery())
        #expect(listed.first { $0.id == entry.id }?.entry.createdAt == written, "the index has the new date")
        withExtendedLifetime(temp) {}
    }

    @Test("importing treats .md, .markdown and .txt files as notes by default (config)")
    func seededNoteExtensions() throws {
        let seeded = try SettingsStore(database: makeSeededDatabase()).string(SettingKeys.importNoteExtensions)
        #expect(NoteImport.extensions(fromSetting: seeded) == ["md", "markdown", "txt"])
    }

    @Test("imported notes are indexed right away, and their passages are refreshed once for the whole import")
    func importNotes() async throws {
        let calls = Mutex(0)
        var (library, _, _, temp) = try setUp(onChange: { calls.withLock { $0 += 1 } })
        library.noteExtensions = ["md"]
        let notes = temp.url.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("# Wohnung\nBesichtigung in Kreuzberg am Samstag".utf8).write(
            to: notes.appendingPathComponent("wohnung.md"))
        try Data("# Laufen\nZehn Kilometer an der Spree".utf8).write(to: notes.appendingPathComponent("laufen.md"))

        let report = try await library.importNotes(from: [notes])

        #expect(report.imported.count == 2)
        #expect(calls.withLock { $0 } == 1)
        let found = try await library.search(EntryQuery(text: "Kreuzberg"))
        #expect(found.map { $0.entry.source } == [.appleNotes])
        #expect(try await library.importNotes(from: [notes]).alreadyHere.count == 2)
    }

    @Test("a whatsapp chat picked as notes is imported as its messages, indexed right away")
    func importChatAsNotes() async throws {
        let calls = Mutex(0)
        var (library, _, _, temp) = try setUp(onChange: { calls.withLock { $0 += 1 } })
        library.noteExtensions = ["txt"]
        let chat = temp.url.appendingPathComponent("_chat.txt")
        try Data(
            ("[12.09.26, 10:15:00] yannik: Besichtigung in Kreuzberg am Samstag\r\n"
                + "[12.09.26, 18:40:12] yannik: Zehn Kilometer an der Spree\r\n").utf8
        ).write(to: chat)

        let report = try await library.importNotes(from: [chat])

        #expect(report.imported.isEmpty)
        #expect(report.chats.imported.count == 2)
        #expect(calls.withLock { $0 } == 1)
        let found = try await library.search(EntryQuery(text: "Kreuzberg"))
        #expect(found.map { $0.entry.source } == [.whatsApp])
    }

    @Test("messages from a whatsapp chat are indexed right away, and their passages are refreshed once")
    func importChats() async throws {
        let calls = Mutex(0)
        let (library, _, _, temp) = try setUp(onChange: { calls.withLock { $0 += 1 } })
        let chat = temp.url.appendingPathComponent("WhatsApp Chat - You/_chat.txt")
        try FileManager.default.createDirectory(
            at: chat.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(
            ("[12.09.26, 10:15:00] yannik: Besichtigung in Kreuzberg am Samstag\r\n"
                + "[12.09.26, 18:40:12] yannik: Zehn Kilometer an der Spree\r\n").utf8
        ).write(to: chat)

        let report = try await library.importChats(from: [chat])

        #expect(report.imported.count == 2)
        #expect(calls.withLock { $0 } == 1)
        let found = try await library.search(EntryQuery(text: "Kreuzberg"))
        #expect(found.map { $0.entry.source } == [.whatsApp])
        #expect(try await library.importChats(from: [chat]).alreadyHere == 2)
    }
}

@Suite("A thought's concepts and summary in Explore")
struct LiveMeaningTests {
    @Test("concept positions are only shown while the Text is the one they were found in")
    func positionsFollowText() async throws {
        let temp = try TemporaryDirectory()
        let files = EntryFileStore(storage: PlainFolderStorage(root: temp.url), calendar: berlinCalendar)
        let database = try makeSeededDatabase()
        let index = EntryIndex(database: database)
        let fragments = FragmentStore(database: database)
        let store = UnderstandingStore(database: database)
        var entry = try files.createTypedEntry(text: "Mit Kim.", createdAt: sampleDate)
        try index.upsert(entry, transcript: nil)
        try fragments.replace(
            entryID: entry.id, spans: [TextSpan(text: "Mit Kim.", utf16Range: 0..<8)], sourceText: entry.text,
            method: "test@1")
        try store.replace(
            entryID: entry.id, sourceText: entry.text,
            understanding: Understanding(
                summary: "Kurz.", mentions: [ConceptMention(kind: "person", name: "Kim", utf16Range: 4..<7)]),
            provenance: .init(modelID: "m", promptRefs: "p"))
        let library = LiveExploreLibrary(
            files: files, index: index,
            search: HybridSearch(
                index: index, fragments: fragments, vectors: VectorStore(database: database),
                resolver: ModelResolver(
                    database: database, registeredEngines: [], installation: ModelInstallation(root: temp.url),
                    conditions: { RuntimeConditions(onBattery: false) }),
                embedders: FakeEmbedderProvider(), settings: SettingsStore(database: database)),
            understandings: store, curation: CurationStore(storage: PlainFolderStorage(root: temp.url)))

        #expect(try await library.meaning(id: entry.id).concepts.map(\.name) == ["Kim"])

        entry.text = "Gestern: mit Kim."
        try index.upsert(entry, transcript: nil)
        let meaning = try await library.meaning(id: entry.id)
        #expect(meaning.concepts.isEmpty)
        #expect(meaning.summary == "Kurz.")
    }
}
