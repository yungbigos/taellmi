import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Entry index in SQLite")
struct EntryIndexTests {
    @Test("indexed entries come back newest first, with segments")
    func indexAndFetch() throws {
        let database = try makeDatabase()
        let index = EntryIndex(database: database)
        let older = Entry(id: "a", createdAt: sampleDate, durationSeconds: 1, source: .voice, folder: "entries/a")
        var newer = Entry(
            id: "b", createdAt: sampleDate.addingTimeInterval(60), durationSeconds: 5.6, source: .voice,
            folder: "entries/b")
        newer.transcriptModelID = germanTranscript.modelID
        newer.text = germanTranscript.text

        try index.upsert(older, transcript: nil)
        try index.upsert(newer, transcript: germanTranscript)

        #expect(try index.recent(limit: 10).map(\.id) == ["b", "a"])
        #expect(try index.segments(entryID: "b") == germanTranscript.segments)
    }

    @Test("upserting again replaces segments instead of duplicating them")
    func upsertReplaces() throws {
        let index = EntryIndex(database: try makeDatabase())
        let entry = Entry(id: "b", createdAt: sampleDate, durationSeconds: 5.6, source: .voice, folder: "entries/b")
        try index.upsert(entry, transcript: germanTranscript)
        try index.upsert(entry, transcript: germanTranscript)
        #expect(try index.segments(entryID: "b").count == 2)
    }

    @Test("the whole index can be rebuilt from the files on disk")
    func rebuildFromDisk() throws {
        let temp = try TemporaryDirectory()
        let files = EntryFileStore(storage: PlainFolderStorage(root: temp.url), calendar: berlinCalendar)
        let entry = try files.createVoiceEntry(
            Recording(file: try temp.makeAudioFile(), durationSeconds: 5.6, startedAt: sampleDate), id: "a1b2")
        let transcribed = try files.saveTranscript(germanTranscript, for: entry)
        _ = try files.createVoiceEntry(
            Recording(
                file: try temp.makeAudioFile(named: "2.m4a"), durationSeconds: 2,
                startedAt: sampleDate.addingTimeInterval(10)),
            id: "c3d4")

        let index = EntryIndex(database: try makeDatabase())
        let report = try index.rebuild(from: files)

        #expect(report.indexed == 2)
        #expect(try index.entry(id: transcribed.id) == transcribed)
        #expect(try index.segments(entryID: transcribed.id) == germanTranscript.segments)
    }
}

@Suite("Rebuilding the index from the Archive")
struct EntryIndexRebuildTests {
    @Test("an unreadable entry.md is skipped and reported, the rest is indexed")
    func skipsInvalidFiles() throws {
        let temp = try TemporaryDirectory()
        let storage = PlainFolderStorage(root: temp.url)
        let files = EntryFileStore(storage: storage, calendar: berlinCalendar)
        _ = try files.createVoiceEntry(
            Recording(file: try temp.makeAudioFile(), durationSeconds: 1, startedAt: sampleDate), id: "good")
        try storage.write(Data("kein front matter".utf8), to: "entries/broken/entry.md")

        let report = try EntryIndex(database: try makeDatabase()).rebuild(from: files)

        #expect(report.indexed == 1)
        #expect(report.invalidFolders == ["entries/broken"])
    }

    @Test("segments disappear from the index once the transcript is gone")
    func dropsStaleSegments() throws {
        let temp = try TemporaryDirectory()
        let files = EntryFileStore(storage: PlainFolderStorage(root: temp.url), calendar: berlinCalendar)
        let entry = try files.saveTranscript(
            germanTranscript,
            for: try files.createVoiceEntry(
                Recording(file: try temp.makeAudioFile(), durationSeconds: 1, startedAt: sampleDate)))
        let index = EntryIndex(database: try makeDatabase())
        try index.rebuild(from: files)
        #expect(try index.segments(entryID: entry.id).count == 2)

        try FileManager.default.removeItem(
            at: temp.url.appendingPathComponent(entry.folder).appendingPathComponent("transcript.json"))
        try index.rebuild(from: files)

        #expect(try index.segments(entryID: entry.id).isEmpty)
    }

    @Test("an Entry awaits transcription only while it has never been transcribed")
    func awaitingTranscription() throws {
        let index = EntryIndex(database: try makeDatabase())
        let fresh = Entry(id: "fresh", createdAt: sampleDate, durationSeconds: 1, source: .voice, folder: "a")
        let cleared = Entry(
            id: "cleared", createdAt: sampleDate, durationSeconds: 1, source: .voice, folder: "b", text: "",
            transcriptModelID: "parakeet")
        let typed = Entry(id: "typed", createdAt: sampleDate, durationSeconds: nil, source: .typed, folder: "c")
        for entry in [fresh, cleared, typed] { try index.upsert(entry, transcript: nil) }
        #expect(try index.awaitingTranscription().map(\.id) == ["fresh"])
    }
}

@Suite("Watching the entry index")
struct EntryIndexObservationTests {
    @Test("emits the current Entries, then again when one changes")
    func emitsChanges() async throws {
        let index = EntryIndex(database: try makeDatabase())
        var entry = Entry(id: "a", createdAt: sampleDate, durationSeconds: 1, source: .voice, folder: "entries/a")
        try index.upsert(entry, transcript: nil)

        var iterator = index.recentUpdates(limit: 5).makeAsyncIterator()
        #expect(await iterator.next()?.map(\.text) == [""])

        entry.text = "Jetzt mit Text."
        try index.upsert(entry, transcript: nil)
        #expect(await iterator.next()?.map(\.text) == ["Jetzt mit Text."])
    }
}
