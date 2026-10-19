import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Entry files in the Archive")
struct EntryFileStoreTests {
    private func makeStore(_ temp: TemporaryDirectory) -> EntryFileStore {
        EntryFileStore(storage: PlainFolderStorage(root: temp.url), calendar: berlinCalendar)
    }

    private func voiceEntry(_ store: EntryFileStore, _ temp: TemporaryDirectory) throws -> Entry {
        try store.createVoiceEntry(
            Recording(file: try temp.makeAudioFile(), durationSeconds: 5.6, startedAt: sampleDate), suffix: "a1b2")
    }

    @Test("a voice entry becomes a dated folder with recording.m4a and entry.md")
    func createsFolder() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        let audio = try temp.makeAudioFile()

        let entry = try store.createVoiceEntry(
            Recording(file: audio, durationSeconds: 63.2, startedAt: sampleDate), suffix: "a1b2")

        #expect(entry.id == "20261019-203412-a1b2")
        #expect(entry.folder == "entries/2026/10/20261019-203412-a1b2")
        #expect(entry.source == .voice)
        let folder = temp.url.appendingPathComponent(entry.folder)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("recording.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: audio.path), "the recording is moved, not copied")
        let document = try EntryDocument(
            markdown: String(contentsOf: folder.appendingPathComponent("entry.md"), encoding: .utf8))
        #expect(document.metadata["id"] == .string(entry.id))
        #expect(document.metadata["source"] == .string("voice"))
        #expect(document.metadata["duration_s"] == .number(63.2))
        #expect(document.body.isEmpty)
    }

    @Test("the first transcript becomes the Text and is kept as transcript.json")
    func firstTranscriptSeedsText() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        let entry = try voiceEntry(store, temp)

        let updated = try store.saveTranscript(germanTranscript, for: entry)

        #expect(updated.text == germanTranscript.text)
        #expect(updated.transcriptModelID == germanTranscript.modelID)
        let loaded = try store.loadEntry(folder: entry.folder)
        #expect(loaded.entry == updated)
        #expect(loaded.transcript == germanTranscript)
        let body = try String(
            contentsOf: temp.url.appendingPathComponent(entry.folder).appendingPathComponent("entry.md"),
            encoding: .utf8)
        #expect(body.hasSuffix("\n\n" + germanTranscript.text + "\n"))
    }

    @Test("a later transcript replaces transcript.json but never changes the Text")
    func laterTranscriptKeepsText() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        let entry = try store.saveTranscript(germanTranscript, for: try voiceEntry(store, temp))

        var edited = entry
        edited.text = "Mein eigener, korrigierter Text über die Zukunftsangst."
        try store.saveText(edited)

        var newer = germanTranscript
        newer.modelID = "better-model"
        newer.text = "Ganz andere Erkennung."
        let updated = try store.saveTranscript(newer, for: edited)

        #expect(updated.text == edited.text)
        let loaded = try store.loadEntry(folder: entry.folder)
        #expect(loaded.entry.text == edited.text)
        #expect(loaded.transcript?.modelID == "better-model")
    }

    @Test("Text survives with umlauts, ß and English mixed in")
    func textRoundTrip() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        var entry = try voiceEntry(store, temp)
        entry.text = "Straße, Grüße, Zukunftsängste – honestly, it's fine.\n\nZweiter Absatz."
        try store.saveText(entry)
        #expect(try store.loadEntry(folder: entry.folder).entry.text == entry.text)
    }

    @Test("an imported Entry keeps an open Source value")
    func openSource() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        var entry = try voiceEntry(store, temp)
        entry.source = EntrySource(rawValue: "obsidian")
        try store.saveText(entry)
        #expect(try store.loadEntry(folder: entry.folder).entry.source.rawValue == "obsidian")
    }

    @Test("lists every entry folder in the Archive, oldest first")
    func listsFolders() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        for (index, suffix) in ["aaaa", "bbbb"].enumerated() {
            _ = try store.createVoiceEntry(
                Recording(
                    file: try temp.makeAudioFile(named: "\(suffix).m4a"), durationSeconds: 1,
                    startedAt: sampleDate.addingTimeInterval(Double(index) * 86_400 * 40)),
                suffix: suffix)
        }
        #expect(
            try store.allEntryFolders() == [
                "entries/2026/10/20261019-203412-aaaa", "entries/2026/11/20261128-193412-bbbb",
            ])
    }

    @Test("transcription keeps edits made on disk and front-matter keys the app doesn't know")
    func keepsDiskEditsAndUnknownKeys() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        let entry = try voiceEntry(store, temp)
        let file = temp.url.appendingPathComponent(entry.folder).appendingPathComponent("entry.md")
        var document = try EntryDocument(markdown: String(contentsOf: file, encoding: .utf8))
        document.metadata["tags"] = .array([.string("obsidian-tag")])
        document.metadata["title"] = .string("Mein Titel")
        try document.markdown().write(to: file, atomically: true, encoding: .utf8)

        let stale = entry  // the caller's copy doesn't know about the edits
        _ = try store.saveTranscript(germanTranscript, for: stale)

        let after = try EntryDocument(markdown: String(contentsOf: file, encoding: .utf8))
        #expect(after.metadata["tags"] == .array([.string("obsidian-tag")]))
        #expect(after.metadata["title"] == .string("Mein Titel"))
        #expect(after.body == germanTranscript.text + "\n")
    }

    @Test("a Text the user cleared is not refilled by a later transcript")
    func clearedTextStaysCleared() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        var entry = try store.saveTranscript(germanTranscript, for: try voiceEntry(store, temp))
        entry.text = ""
        try store.saveText(entry)

        var newer = germanTranscript
        newer.modelID = "better-model"
        _ = try store.saveTranscript(newer, for: entry)

        #expect(try store.loadEntry(folder: entry.folder).entry.text.isEmpty)
    }

    @Test("knows whether an Entry still has its recording")
    func recordingPresence() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        let entry = try voiceEntry(store, temp)
        #expect(store.hasRecording(entry))
        try FileManager.default.removeItem(
            at: temp.url.appendingPathComponent(entry.folder).appendingPathComponent("recording.m4a"))
        #expect(!store.hasRecording(entry))
    }

    @Test("a failed import leaves no half-made Entry folder behind")
    func noHalfMadeFolders() throws {
        let temp = try TemporaryDirectory()
        let store = makeStore(temp)
        let missing = temp.url.appendingPathComponent("does-not-exist.m4a")
        #expect(throws: (any Error).self) {
            try store.createVoiceEntry(Recording(file: missing, durationSeconds: 1, startedAt: sampleDate))
        }
        #expect(try store.allEntryFolders().isEmpty)
    }
}
