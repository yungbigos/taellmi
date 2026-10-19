import Domain
import Features
import Foundation
import Persistence

/// Explore on the real Archive: Text and Recording come from the Entry folders, search from the index.
nonisolated struct LiveExploreLibrary: ExploreLibrary {
    let files: EntryFileStore
    let index: EntryIndex

    func search(_ query: EntryQuery) async throws -> [Entry] {
        try index.search(query)
    }

    func changes() -> AsyncStream<Void> {
        index.changes()
    }

    func detail(id: String) async throws -> EntryDetail {
        guard let indexed = try index.entry(id: id) else { throw CocoaError(.fileNoSuchFile) }
        let loaded = try files.loadEntry(folder: indexed.folder)
        return EntryDetail(
            entry: loaded.entry, segments: loaded.transcript?.segments ?? [], corrections: loaded.corrections,
            recordingURL: files.hasRecording(loaded.entry) ? try files.recordingURL(for: loaded.entry) : nil)
    }

    func createThought(text: String) async throws -> Entry {
        let entry = try files.createTypedEntry(text: text, createdAt: Date())
        try index.upsert(entry, transcript: nil)
        return entry
    }

    func saveText(id: String, text: String) async throws {
        guard let indexed = try index.entry(id: id) else { throw CocoaError(.fileNoSuchFile) }
        let loaded = try files.loadEntry(folder: indexed.folder)
        var entry = loaded.entry
        entry.text = text
        try files.saveText(entry)
        try index.upsert(entry, transcript: loaded.transcript)
    }

    func trash(id: String) async throws -> String {
        guard let entry = try index.entry(id: id) else { throw CocoaError(.fileNoSuchFile) }
        let trashed = try files.moveToTrash(entry)
        try index.remove(id: id)
        return trashed
    }

    func restore(trashedFolder: String) async throws {
        let entry = try files.restoreFromTrash(trashedFolder: trashedFolder)
        try index.upsert(entry, transcript: try files.loadEntry(folder: entry.folder).transcript)
    }

    func trashed() async throws -> [TrashedEntry] {
        try files.trashedFolders()
            .compactMap { folder in
                (try? files.loadEntry(folder: folder)).map { TrashedEntry(entry: $0.entry, trashedFolder: folder) }
            }
            .sorted { $0.entry.createdAt > $1.entry.createdAt }
    }

    func deleteForever(trashedFolder: String) async throws {
        try files.deleteFromTrash(trashedFolder: trashedFolder)
    }
}
