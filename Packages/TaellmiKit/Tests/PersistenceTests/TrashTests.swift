import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("The app's Trash")
struct TrashTests {
    private func setUp() throws -> (EntryFileStore, EntryIndex, Entry, TemporaryDirectory) {
        let temp = try TemporaryDirectory()
        let files = EntryFileStore(storage: PlainFolderStorage(root: temp.url), calendar: berlinCalendar)
        let index = EntryIndex(database: try makeDatabase())
        let entry = try files.createTypedEntry(text: "Wegwerfen?", createdAt: sampleDate, suffix: "tr45")
        try index.upsert(entry, transcript: nil)
        return (files, index, entry, temp)
    }

    @Test("trashing moves the Entry folder into the Trash and out of the list and the index")
    func trash() throws {
        let (files, index, entry, temp) = try setUp()
        let trashed = try files.moveToTrash(entry)
        try index.remove(id: entry.id)

        #expect(try files.allEntryFolders().isEmpty)
        #expect(try files.trashedFolders() == [trashed])
        #expect(try index.entry(id: entry.id) == nil)
        #expect(try files.loadEntry(folder: trashed).entry.text == "Wegwerfen?")
        withExtendedLifetime(temp) {}
    }

    @Test("restoring puts the folder back where it was")
    func restore() throws {
        let (files, _, entry, temp) = try setUp()
        let trashed = try files.moveToTrash(entry)
        let restored = try files.restoreFromTrash(trashedFolder: trashed)
        #expect(restored.folder == entry.folder)
        #expect(try files.allEntryFolders() == [entry.folder])
        #expect(try files.trashedFolders().isEmpty)
        withExtendedLifetime(temp) {}
    }

    @Test("a rebuilt index does not bring trashed Entries back")
    func rebuildIgnoresTrash() throws {
        let (files, index, entry, temp) = try setUp()
        _ = try files.moveToTrash(entry)
        try index.rebuild(from: files)
        #expect(try index.entry(id: entry.id) == nil)
        withExtendedLifetime(temp) {}
    }
}
