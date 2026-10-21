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
    /// File extensions that count as notes when importing (config: `import.note_extensions`).
    var noteExtensions: Set<String> = []

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

    // MARK: stack: folders (curation.json) and concepts

    func stackIndex() async throws -> StackIndex {
        let library = self
        return try await Task.detached(priority: .userInitiated) {
            let folders = try library.curation?.folders() ?? []
            let filed = try library.curation?.filed() ?? [:]
            let all = Set(try library.index.allIDs())
            let live = filed.filter { all.contains($0.key) }
            return StackIndex(
                folders: folders.map { folder in
                    FolderSummary(folder: folder, count: live.values.filter { $0 == folder.id }.count)
                },
                concepts: try library.understandings?.concepts() ?? [],
                looseCount: all.count - live.count)
        }.value
    }

    func thoughtIDs(in group: StackGroup) async throws -> Set<String> {
        let library = self
        return try await Task.detached(priority: .userInitiated) {
            let filed = try library.curation?.filed() ?? [:]
            switch group {
            case .loose: return Set(try library.index.allIDs()).filter { filed[$0] == nil }
            case .folder(let id): return Set(filed.filter { $0.value == id }.keys)
            case .concept(let id): return Set(try library.understandings?.entryIDs(mentioning: id) ?? [])
            }
        }.value
    }

    func createFolder(named name: String) async throws -> ThoughtFolder {
        guard let curation else { throw CocoaError(.featureUnsupported) }
        let folder = try curation.createFolder(named: name)
        onChange()
        return folder
    }

    func renameFolder(_ id: String, to name: String) async throws {
        try curation?.renameFolder(id, to: name)
    }

    func deleteFolder(_ id: String) async throws {
        try curation?.deleteFolder(id)
    }

    func conceptCuration() async throws -> ConceptCuration {
        try curation?.conceptCuration() ?? ConceptCuration()
    }

    func saveConceptCuration(_ concepts: ConceptCuration, addSpelling: String?) async throws {
        try curation?.setConceptCuration(concepts, addingTerm: addSpelling)
        let library = self
        try await Task.detached(priority: .userInitiated) { try library.understandings?.apply(concepts) }.value
    }

    func folderID(of entryID: String) async throws -> String? {
        try curation?.filed()[entryID]
    }

    func file(_ entryID: String, in folderID: String?) async throws {
        try curation?.file(entryID, in: folderID)
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

    func importNotes(from urls: [URL]) async throws -> NoteImportReport {
        let library = self
        return try await Task.detached(priority: .userInitiated) {
            // Files the panel handed over are readable while tällmi runs; folders kept in a bookmark need this.
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
            let report = try NoteImport(
                files: library.files, source: .appleNotes, extensions: library.noteExtensions
            ).run(urls)
            // The thoughts are written either way; one that can't be indexed now is indexed on the next start.
            for entry in report.imported { try? library.index.upsert(entry, transcript: nil) }
            if !report.imported.isEmpty { library.onChange() }
            return report
        }.value
    }

    func setDate(id: String, to date: Date) async throws {
        guard let indexed = try index.entry(id: id) else { throw CocoaError(.fileNoSuchFile) }
        let loaded = try files.loadEntry(folder: indexed.folder)
        var entry = loaded.entry
        entry.createdAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        try files.saveText(entry)
        try index.upsert(entry, transcript: loaded.transcript)
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
