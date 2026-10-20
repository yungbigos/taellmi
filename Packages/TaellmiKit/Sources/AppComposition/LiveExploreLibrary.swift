import Domain
import Features
import Foundation
import Persistence
import Search

/// Explore on the real Archive: Text and Recording come from the Entry folders, search from the index.
nonisolated struct LiveExploreLibrary: ExploreLibrary {
    let files: EntryFileStore
    let index: EntryIndex
    let search: HybridSearch
    /// Called after a Text was written, so its passages and vectors are refreshed soon.
    var onChange: @Sendable () -> Void = {}
    /// Summaries and concepts (ADR 0012), related thoughts, and your edited summaries. Optional, so the
    /// library also works without them.
    var understandings: UnderstandingStore?
    var related: RelatedThoughts?
    var curation: CurationStore?

    // These read the database and search vectors, so they run off the main actor.

    func meaning(id: String) async throws -> ThoughtMeaning {
        let library = self
        return try await Task.detached(priority: .userInitiated) {
            let understood = try library.understandings?.understanding(entryID: id)
            let edited = try library.curation?.summary(for: id)
            // Positions only fit the Text they were found in; after an edit they wait for the next analysis.
            let current = try library.index.entry(id: id)?.text
            let concepts = understood?.sourceText == current ? understood?.concepts ?? [] : []
            return ThoughtMeaning(
                summary: edited ?? understood?.summary, summaryIsEdited: edited != nil, concepts: concepts,
                related: try library.related?.related(to: id) ?? [])
        }.value
    }

    func concepts() async throws -> [ConceptSummary] {
        let understandings = understandings
        return try await Task.detached(priority: .userInitiated) { try understandings?.concepts() ?? [] }.value
    }

    func conceptKinds() async throws -> [ConceptKind] {
        try understandings?.conceptKindDetails() ?? []
    }

    func conceptDetail(id: String) async throws -> ConceptDetail {
        let library = self
        return try await Task.detached(priority: .userInitiated) {
            guard let understandings = library.understandings,
                let concept = try understandings.concepts().first(where: { $0.id == id })
            else { throw CocoaError(.fileNoSuchFile) }
            return ConceptDetail(
                concept: concept,
                thoughts: try understandings.entryIDs(mentioning: id).compactMap { try library.index.entry(id: $0) },
                appearingWith: try understandings.appearingWith(id))
        }.value
    }

    func saveSummary(id: String, text: String?) async throws {
        try curation?.setSummary(text, for: id)
    }

    /// Newest first without search words; with them, thoughts with the words, then related ones.
    func search(_ query: EntryQuery) async throws -> [SearchHit] {
        try await search.hits(query)
    }

    /// Entries changed, or the pipeline stored new concepts and summaries.
    func changes() -> AsyncStream<Void> {
        let streams = [index.changes()] + (understandings.map { [$0.changes()] } ?? [])
        return AsyncStream { continuation in
            let tasks = streams.map { stream in
                Task {
                    for await _ in stream { continuation.yield() }
                }
            }
            continuation.onTermination = { _ in for task in tasks { task.cancel() } }
        }
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
        onChange()
        return entry
    }

    func saveText(id: String, text: String) async throws {
        guard let indexed = try index.entry(id: id) else { throw CocoaError(.fileNoSuchFile) }
        let loaded = try files.loadEntry(folder: indexed.folder)
        var entry = loaded.entry
        entry.text = text
        try files.saveText(entry)
        try index.upsert(entry, transcript: loaded.transcript)
        onChange()
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

    // Trash is file work, so it runs off the main actor; the bar asks for the count on every refresh.
    func trashed() async throws -> [TrashedEntry] {
        let files = files
        return try await Task.detached(priority: .utility) {
            try files.trashedFolders()
                .compactMap { folder in
                    (try? files.loadEntry(folder: folder)).map { TrashedEntry(entry: $0.entry, trashedFolder: folder) }
                }
                .sorted { $0.entry.createdAt > $1.entry.createdAt }
        }.value
    }

    func trashedCount() async throws -> Int {
        let files = files
        return try await Task.detached(priority: .utility) { try files.trashedFolders().count }.value
    }

    func deleteForever(trashedFolder: String) async throws {
        let library = self
        try await Task.detached(priority: .utility) {
            let id = try? library.files.loadEntry(folder: trashedFolder).entry.id
            try library.files.deleteFromTrash(trashedFolder: trashedFolder)
            // Your own summary is your text too; it goes with the thought.
            if let id { try library.curation?.setSummary(nil, for: id) }
        }.value
    }
}
