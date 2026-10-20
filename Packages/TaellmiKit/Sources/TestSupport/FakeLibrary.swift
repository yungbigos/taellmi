import Domain
import Features
import Foundation

/// An in-memory Archive for Explore tests.
public actor FakeLibrary: ExploreLibrary {
    public private(set) var savedTexts: [String: String] = [:]
    public private(set) var savedSummaries: [String: String?] = [:]
    private var meanings: [String: ThoughtMeaning] = [:]
    private var conceptList: [ConceptSummary] = []
    private var conceptDetails: [String: ConceptDetail] = [:]
    private var entries: [Entry]
    private var trash: [String: Entry] = [:]
    private var trashListingFails = false
    private var continuations: [AsyncStream<Void>.Continuation] = []
    private var related: [(id: String, passage: Range<Int>)] = []
    private var heldTexts: Set<String> = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    private var importReport = NoteImportReport()
    private var importsFail = false
    public private(set) var importedFrom: [URL]?

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The next search for exactly `text` waits until `releaseHeldSearches()`, like a slow search (e.g. one
    /// that first loads a model) that finishes after a later one. Later searches for it run normally.
    public func holdSearches(for text: String) {
        heldTexts.insert(text)
    }

    /// Waits until a held search has started.
    public func waitUntilASearchIsHeld() async {
        if !held.isEmpty { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    /// Every search with words also returns this thought as related (found only by meaning), with the
    /// passage that matched, unless it already matches by words.
    public func relate(_ id: String, passage: Range<Int>) {
        related.append((id, passage))
    }

    /// What `meaning(id:)` returns for a thought; a change is announced like any Archive change.
    public func setMeaning(_ meaning: ThoughtMeaning, for id: String) {
        meanings[id] = meaning
        publish()
    }

    public func setConcepts(_ concepts: [ConceptSummary], details: [ConceptDetail] = []) {
        conceptList = concepts
        conceptDetails = Dictionary(uniqueKeysWithValues: details.map { ($0.concept.id, $0) })
    }

    public func meaning(id: String) async throws -> ThoughtMeaning {
        var meaning = meanings[id] ?? .empty
        if let saved = savedSummaries[id] {
            meaning.summary = saved
            meaning.summaryIsEdited = saved != nil
        }
        return meaning
    }

    public func concepts() async throws -> [ConceptSummary] { conceptList }

    public func conceptKinds() async throws -> [ConceptKind] {
        [
            ConceptKind(id: "person", plural: "people", symbol: "person"),
            ConceptKind(id: "place", plural: "places", symbol: "mappin"),
            ConceptKind(id: "topic", plural: "topics", symbol: "number"),
            ConceptKind(id: "emotion", plural: "feelings", symbol: "heart"),
        ]
    }

    public func conceptDetail(id: String) async throws -> ConceptDetail {
        guard let detail = conceptDetails[id] else { throw CocoaError(.fileNoSuchFile) }
        return detail
    }

    public func saveSummary(id: String, text: String?) async throws {
        savedSummaries[id] = text
        publish()
    }

    public func releaseHeldSearches() {
        heldTexts.removeAll()
        for search in held { search.resume() }
        held.removeAll()
    }

    public func search(_ query: EntryQuery) async throws -> [SearchHit] {
        // The answer is computed now and handed back later, like a slow search over the Archive as it was.
        let hits = answer(query)
        if heldTexts.remove(query.text) != nil {
            await withCheckedContinuation { continuation in
                held.append(continuation)
                for waiter in heldWaiters { waiter.resume() }
                heldWaiters.removeAll()
            }
        }
        return hits
    }

    private func answer(_ query: EntryQuery) -> [SearchHit] {
        let words =
            entries
            .filter { entry in query.words.allSatisfy { entry.text.lowercased().contains($0) } }
            .filter { query.sources?.contains($0.source) ?? true }
            .filter { entry in
                query.earliestDate(now: Date(), calendar: .current).map { entry.createdAt >= $0 } ?? true
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map { SearchHit(entry: $0, match: .words, wordRanges: TextMatch.ranges(of: query.words, in: $0.text)) }
        guard !query.words.isEmpty else { return words }
        let wordIDs = Set(words.map(\.id))
        let relatedHits = related.compactMap { item -> SearchHit? in
            guard !wordIDs.contains(item.id), let entry = entries.first(where: { $0.id == item.id }) else { return nil }
            return SearchHit(entry: entry, match: .related, passage: item.passage)
        }
        return words + relatedHits
    }

    public nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in Task { await self.subscribe(continuation) } }
    }

    public func detail(id: String) async throws -> EntryDetail {
        guard let entry = entries.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        return EntryDetail(entry: entry, segments: [], corrections: [], recordingURL: nil)
    }

    public func createThought(text: String) async throws -> Entry {
        let entry = Entry(
            id: "new-\(entries.count + trash.count + 1)", createdAt: Date(), durationSeconds: nil, source: .typed,
            folder: "entries/new-\(entries.count + trash.count + 1)", text: text)
        entries.append(entry)
        publish()
        return entry
    }

    public func setDate(id: String, to date: Date) async throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        entries[index].createdAt = date
        publish()
    }

    public func saveText(id: String, text: String) async throws {
        savedTexts[id] = text
        if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].text = text }
        publish()
    }

    public func trash(id: String) async throws -> String {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        let entry = entries.remove(at: index)
        let token = "trash/\(entry.folder)"
        trash[token] = entry
        publish()
        return token
    }

    public func restore(trashedFolder: String) async throws {
        guard let entry = trash.removeValue(forKey: trashedFolder) else { throw CocoaError(.fileNoSuchFile) }
        entries.append(entry)
        publish()
    }

    /// From now on, reading the trash fails, as with a folder that can't be read.
    public func failTrashListing() { trashListingFails = true }

    public func trashedCount() async throws -> Int {
        if trashListingFails { throw CocoaError(.fileReadNoPermission) }
        return trash.count
    }

    public func trashed() async throws -> [TrashedEntry] {
        if trashListingFails { throw CocoaError(.fileReadNoPermission) }
        return trash.map { TrashedEntry(entry: $0.value, trashedFolder: $0.key) }.sorted {
            $0.entry.createdAt > $1.entry.createdAt
        }
    }

    public func deleteForever(trashedFolder: String) async throws {
        trash[trashedFolder] = nil
        publish()
    }

    /// What the next import returns; its thoughts join the Archive.
    public func setImportReport(_ report: NoteImportReport) {
        importReport = report
    }

    public func failImports() {
        importsFail = true
    }

    public func importNotes(from urls: [URL]) async throws -> NoteImportReport {
        importedFrom = urls
        if importsFail { throw CocoaError(.fileReadNoPermission) }
        entries += importReport.imported
        publish()
        return importReport
    }

    private func subscribe(_ continuation: AsyncStream<Void>.Continuation) { continuations.append(continuation) }
    private func publish() { for continuation in continuations { continuation.yield() } }
}
