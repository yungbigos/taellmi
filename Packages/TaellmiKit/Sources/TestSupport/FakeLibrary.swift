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
    private var conceptMentions: [String: [String]] = [:]
    private var folderList: [ThoughtFolder] = []
    private var filedIn: [String: String] = [:]
    private var entries: [Entry]
    private var trash: [String: Entry] = [:]
    private var trashListingFails = false
    private var continuations: [AsyncStream<Void>.Continuation] = []
    private var related: [(id: String, passage: Range<Int>)] = []
    private var heldTexts: Set<String> = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    private var importReport = NoteImportReport()
    private var chatImportReport = ChatImportReport()
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

    /// `mentions`: which thoughts name each concept, for stack's concept groups.
    public func setConcepts(
        _ concepts: [ConceptSummary], details: [ConceptDetail] = [], mentions: [String: [String]] = [:]
    ) {
        conceptList = concepts
        conceptDetails = Dictionary(uniqueKeysWithValues: details.map { ($0.concept.id, $0) })
        conceptMentions = mentions
    }

    public func stackIndex() async throws -> StackIndex {
        StackIndex(
            folders: folderList.map { folder in
                FolderSummary(folder: folder, count: filedIn.values.filter { $0 == folder.id }.count)
            },
            concepts: curatedConcepts, looseCount: entries.filter { filedIn[$0.id] == nil }.count)
    }

    public func thoughtIDs(in group: StackGroup) async throws -> Set<String> {
        switch group {
        case .loose: Set(entries.map(\.id).filter { filedIn[$0] == nil })
        case .folder(let id): Set(filedIn.filter { $0.value == id }.keys)
        case .concept(let id): Set(conceptMentions[id] ?? [])
        }
    }

    public func createFolder(named name: String) async throws -> ThoughtFolder {
        let folder = ThoughtFolder(id: "folder-\(folderList.count + 1)", name: name)
        folderList.append(folder)
        publish()
        return folder
    }

    public func renameFolder(_ id: String, to name: String) async throws {
        guard let index = folderList.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        folderList[index].name = name
        publish()
    }

    public func deleteFolder(_ id: String) async throws {
        folderList.removeAll { $0.id == id }
        filedIn = filedIn.filter { $0.value != id }
        publish()
    }

    public func folderID(of entryID: String) async throws -> String? { filedIn[entryID] }

    public private(set) var conceptCurationValue = ConceptCuration()
    public private(set) var spellingsAdded: [String] = []

    public func conceptCuration() async throws -> ConceptCuration { conceptCurationValue }

    public func saveConceptCuration(_ curation: ConceptCuration, addSpelling: String?) async throws {
        conceptCurationValue = curation
        if let addSpelling { spellingsAdded.append(addSpelling) }
        publish()
    }

    /// The concepts as your renames and merges make them: merged ones add up under the name that stays.
    private var curatedConcepts: [ConceptSummary] {
        var merged: [String: ConceptSummary] = [:]
        var order: [String] = []
        for concept in conceptList {
            let source = ConceptName(kind: concept.kind, name: concept.name)
            let target = conceptCurationValue.resolve(source)
            // Untouched concepts keep their id; renamed and merged ones take the id of where they went.
            let id = target == source && target.name == source.name ? concept.id : "concept:\(target.key)"
            if merged[id] == nil {
                order.append(id)
                merged[id] = ConceptSummary(id: id, kind: target.kind, name: target.name, thoughtCount: 0)
            }
            merged[id]?.thoughtCount += concept.thoughtCount
        }
        return order.compactMap { merged[$0] }
    }

    public func file(_ entryID: String, in folderID: String?) async throws {
        filedIn[entryID] = folderID
        publish()
    }

    /// How often each thought's meaning was asked for, to check that scrolling doesn't reload it.
    public private(set) var meaningCalls: [String: Int] = [:]
    public private(set) var searchCalls = 0

    public func meaning(id: String) async throws -> ThoughtMeaning {
        meaningCalls[id, default: 0] += 1
        var meaning = meanings[id] ?? .empty
        if let saved = savedSummaries[id] {
            meaning.summary = saved
            meaning.summaryIsEdited = saved != nil
        }
        return meaning
    }

    public func concepts() async throws -> [ConceptSummary] { curatedConcepts }

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
        searchCalls += 1
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
            .map { SearchHit(entry: $0, match: .words, wordRanges: TextMatch.sections(for: query.words, in: $0.text)) }
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
        entries += importReport.imported + importReport.chats.imported
        publish()
        return importReport
    }

    /// What the next chat import returns; its thoughts join the Archive.
    public func setChatImportReport(_ report: ChatImportReport) {
        chatImportReport = report
    }

    public func importChats(from urls: [URL]) async throws -> ChatImportReport {
        importedFrom = urls
        if importsFail { throw CocoaError(.fileReadNoPermission) }
        entries += chatImportReport.imported
        publish()
        return chatImportReport
    }

    private func subscribe(_ continuation: AsyncStream<Void>.Continuation) { continuations.append(continuation) }
    private func publish() { for continuation in continuations { continuation.yield() } }
}
