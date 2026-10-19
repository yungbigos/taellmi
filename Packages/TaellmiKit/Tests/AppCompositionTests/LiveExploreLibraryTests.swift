import Domain
import Features
import Foundation
import Persistence
import TestSupport
import Testing

@testable import AppComposition

@Suite("Explore working on the real Archive")
struct LiveExploreLibraryTests {
    private func setUp() throws -> (LiveExploreLibrary, EntryFileStore, Entry, TemporaryDirectory) {
        let temp = try TemporaryDirectory()
        let files = EntryFileStore(
            storage: PlainFolderStorage(root: temp.url, systemTrash: { try FileManager.default.removeItem(at: $0) }),
            calendar: berlinCalendar)
        let index = EntryIndex(database: try makeDatabase())
        let entry = try files.saveTranscript(
            germanTranscript,
            for: try files.createVoiceEntry(
                Recording(file: try temp.makeAudioFile(), durationSeconds: 5.6, startedAt: sampleDate),
                suffix: "ex01"))
        try index.upsert(entry, transcript: germanTranscript)
        return (LiveExploreLibrary(files: files, index: index), files, entry, temp)
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
}
