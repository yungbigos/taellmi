import Domain
import Foundation
import Observation

/// Asks flow to scroll to a thought; each request is new, even for the same thought.
nonisolated public struct ScrollRequest: Sendable, Equatable {
    public let entryID: String
    public let id = UUID()

    public init(entryID: String) {
        self.entryID = entryID
    }
}

/// One Entry opened in Explore.
nonisolated public struct EntryDetail: Sendable, Equatable {
    public var entry: Entry
    /// From the Transcript, for jumping around in the Recording. Empty when there is none.
    public var segments: [TranscriptSegment]
    public var corrections: [VocabularyCorrection]
    /// nil once the Recording is gone (Retention) or for typed Entries.
    public var recordingURL: URL?

    public init(entry: Entry, segments: [TranscriptSegment], corrections: [VocabularyCorrection], recordingURL: URL?) {
        self.entry = entry
        self.segments = segments
        self.corrections = corrections
        self.recordingURL = recordingURL
    }
}

/// An Entry in the app's Trash.
nonisolated public struct TrashedEntry: Sendable, Equatable, Identifiable {
    public var entry: Entry
    public var trashedFolder: String
    public var id: String { trashedFolder }

    public init(entry: Entry, trashedFolder: String) {
        self.entry = entry
        self.trashedFolder = trashedFolder
    }
}

/// A search a thought was opened from, so it can still be highlighted once the search itself is closed.
struct OpenedSearch: Equatable {
    var text: String
    var hit: SearchHit
}

/// A part of a thought's text to highlight while a search is active.
public struct TextHighlight: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A search word.
        case word
        /// The passage that made a related thought match by meaning.
        case passage
        /// Words that name a concept of this kind (person, place, topic, emotion).
        case concept(String)
    }

    /// UTF-16 range in the text.
    public var range: Range<Int>
    public var kind: Kind

    public init(range: Range<Int>, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

/// What the Explore window needs from the Archive. Implemented in the composition root.
public protocol ExploreLibrary: Sendable {
    /// Newest first without search words; otherwise thoughts with the words, then related ones.
    func search(_ query: EntryQuery) async throws -> [SearchHit]
    /// Fires whenever Entries change (new Entry, Transcript arrived, edit, Trash).
    func changes() -> AsyncStream<Void>
    func detail(id: String) async throws -> EntryDetail
    /// Creates a new typed thought.
    func createThought(text: String) async throws -> Entry
    func saveText(id: String, text: String) async throws
    /// Moves an Entry to the app's Trash; returns where it went, for undo.
    func trash(id: String) async throws -> String
    func restore(trashedFolder: String) async throws
    func trashed() async throws -> [TrashedEntry]
    /// How many thoughts are in trash, without loading them.
    func trashedCount() async throws -> Int
    func deleteForever(trashedFolder: String) async throws
    /// A thought's summary, concepts and related thoughts (ADR 0012).
    func meaning(id: String) async throws -> ThoughtMeaning
    /// Every concept, most-mentioned first.
    func concepts() async throws -> [ConceptSummary]
    /// The kinds of concept, in order, with their words and symbols (config).
    func conceptKinds() async throws -> [ConceptKind]
    func conceptDetail(id: String) async throws -> ConceptDetail
    /// Your own summary for a thought; `nil` brings back the generated one.
    func saveSummary(id: String, text: String?) async throws
    /// stack's index: your folders, the concepts, and how many thoughts are loose.
    func stackIndex() async throws -> StackIndex
    /// The thoughts in a group of stack.
    func thoughtIDs(in group: StackGroup) async throws -> Set<String>
    func createFolder(named name: String) async throws -> ThoughtFolder
    func renameFolder(_ id: String, to name: String) async throws
    func deleteFolder(_ id: String) async throws
    func file(_ entryID: String, in folderID: String?) async throws
    /// The folder a thought is filed in, if any.
    func folderID(of entryID: String) async throws -> String?
    /// Gives a thought another date and time; its Text stays as it is.
    func setDate(id: String, to date: Date) async throws
    /// Turns the chosen note files and folders into thoughts from Apple Notes, skipping notes already here.
    func importNotes(from urls: [URL]) async throws -> NoteImportReport
}

/// State and actions of the Explore window.
@Observable
public final class ExploreViewModel {
    public var query = EntryQuery()
    public var showsTrash = false
    public var view: ExploreViewKind = .stack
    /// In flow: thoughts matching the search, in reading order, and the one jumped to.
    public private(set) var flowMatches: [String] = []
    public private(set) var currentMatch: String?
    /// The thought flow should scroll to (opened from the menu bar, space or a related thought). A new
    /// request each time, so asking for the same thought twice still scrolls.
    public private(set) var scrollRequest: ScrollRequest?
    public var scrollTarget: String? { scrollRequest?.entryID }
    /// Summary, concepts and related thoughts of the thoughts on screen, by id; loaded as they appear.
    public private(set) var meanings: [String: ThoughtMeaning] = [:]
    /// In space: every concept, and the one chosen with everything connected to it.
    public private(set) var concepts: [ConceptSummary] = []
    public private(set) var conceptKinds: [ConceptKind] = []
    /// stack: the group shown (a folder, a concept, or the loose thoughts) and the index beside it.
    public internal(set) var stackGroup: StackGroup = .loose
    public internal(set) var stackIndex: StackIndex = .empty
    public private(set) var conceptDetail: ConceptDetail?
    /// In space: the concepts you picked to filter by, in the order you picked them.
    public private(set) var pickedConcepts: [String] = []
    private var pickedDetails: [String: ConceptDetail] = [:]
    @ObservationIgnored private var pickGeneration = 0
    /// In space: only concepts of this kind (nil: every kind), and only those whose name has these letters.
    public var conceptKindFilter: String?
    public var conceptSearch = ""
    /// Thoughts in trash, for the count in the bar.
    public private(set) var trashCount = 0
    /// In time: the span on screen.
    public var timeRange = TimelineRange(zoom: .week, anchor: Date())
    /// Current shortcut of every command, from config.
    public var shortcuts: [Command: Hotkey] = [:]
    public var isPaletteOpen = false {
        didSet { if isPaletteOpen, !oldValue { formatting.paletteWillOpen() } }
    }
    /// The thought editor formatting from ⌘K goes to.
    @ObservationIgnored public let formatting = FormattingFocus()
    /// Bumped when the recording should play or pause.
    public private(set) var playbackRequest = 0
    /// Bumped when the window should ask which notes to import.
    public private(set) var noteImportRequest = 0
    /// What the last import of notes did, until you dismiss it.
    public var noteImportMessage: String?
    /// True while chosen notes are being imported.
    public private(set) var isImportingNotes = false
    /// Writing a new thought in the full-window composer.
    public private(set) var isComposing = false
    public var composerText = "" {
        didSet { scheduleComposerAutosave() }
    }
    @ObservationIgnored private var composedID: String?
    @ObservationIgnored private var composedSavedText = ""
    @ObservationIgnored private var composerAutosaveTask: Task<Void, Never>?
    public private(set) var entries: [Entry] = []
    /// How the current search found each thought, by id. Empty without search words.
    public private(set) var matches: [String: SearchHit] = [:] {
        didSet { snippets = matches.mapValues { ResultSnippet(hit: $0, maxLength: Self.rowSnippetLength) } }
    }
    /// The excerpt each list row shows while a search is active.
    public private(set) var snippets: [String: ResultSnippet] = [:]
    /// A list row is one line; the match then sits in its first third.
    private static let rowSnippetLength = 90
    public private(set) var trashedEntries: [TrashedEntry] = []
    public private(set) var detail: EntryDetail?
    public internal(set) var errorMessage: String?
    /// The Text being edited; saved automatically shortly after you stop typing.
    public var editorText = "" {
        didSet { scheduleAutosave() }
    }

    @ObservationIgnored let library: any ExploreLibrary
    /// tälli's capture, so the composer can listen like tälli at the cursor.
    public let capture: CaptureViewModel?
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var savedText = ""
    @ObservationIgnored private var lastTrashed: String?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private let changeDebounce: Duration
    /// Thoughts whose meaning is on screen right now (flow and stack blocks).
    @ObservationIgnored private var visibleMeanings: Set<String> = []
    @ObservationIgnored private var refreshGeneration = 0
    /// The search the open thought was opened from (⌘K), while the window's own search field is empty.
    private var openedSearch: OpenedSearch?

    /// - Parameters:
    ///   - autosaveDelay: pause after the last keystroke before saving (from config).
    ///   - startView: the view the window opens in (from config).
    ///   - changeDebounce: Archive changes this close together refresh the window once (from config); the
    ///     pipeline writes many in a row while it works through thoughts.
    public init(
        library: any ExploreLibrary, autosaveDelay: Duration, startView: ExploreViewKind = .stack,
        capture: CaptureViewModel? = nil, changeDebounce: Duration = .zero
    ) {
        self.changeDebounce = changeDebounce
        self.view = startView
        self.capture = capture
        self.library = library
        self.autosaveDelay = autosaveDelay
    }

    /// Re-runs the search (or reloads the Trash) whenever the Archive changes.
    /// Everything the window needs before it shows: the thoughts loaded, kept up to date, and the chosen
    /// thought selected. Independent of the view, so flow and time never open empty.
    public func open(selecting entryID: String?) async {
        if observation == nil { startObserving() }
        if conceptKinds.isEmpty { conceptKinds = (try? await library.conceptKinds()) ?? [] }
        if entryID != nil { showsTrash = false }
        await refresh()
        guard let entryID else {
            await openNewestIfNothingOpen()
            return
        }
        await select(entryID)
        scrollRequest = ScrollRequest(entryID: entryID)
    }

    public func startObserving() {
        observation?.cancel()
        let changes = library.changes()
        let debounce = changeDebounce
        observation = Task { [weak self] in
            var pending: Task<Void, Never>?
            for await _ in changes {
                guard debounce > .zero else {
                    await self?.refresh()
                    continue
                }
                pending?.cancel()
                pending = Task { [weak self] in
                    try? await Task.sleep(for: debounce)
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
    }

    /// Runs a command (from its shortcut or the ⌘K palette).
    public func perform(_ command: Command) async {
        switch command {
        case .openPalette: isPaletteOpen = true
        case .newThought: await startComposing()
        case .deleteThought: await trashSelected()
        // Search lives in ⌘K, opened from the search button at the top right.
        case .searchThoughts: isPaletteOpen = true
        case .showStack: await show(view: .stack)
        case .showFlow: await show(view: .flow)
        case .showTime: await show(view: .time)
        case .showSpace: await show(view: .space)
        case .nextMatch: jumpMatch(by: 1)
        case .previousMatch: jumpMatch(by: -1)
        case .zoomInTime: timeRange.zoomIn()
        case .zoomOutTime: timeRange.zoomOut()
        case .showEarlier: timeRange.moveEarlier()
        case .showLater: timeRange.moveLater()
        case .showTrash: await show(trash: true)
        case .playRecording: playbackRequest += 1
        case .importNotes: noteImportRequest += 1
        case .formatBold, .formatItalic, .formatUnderline, .formatStrikethrough, .formatBulletList,
            .formatNumberedList, .indentListItem, .outdentListItem:
            if let action = command.formattingAction { formatting.applyFromPalette(action) }
        }
    }

    /// Imports the note files and folders you chose and reports what happened.
    public func importNotes(from urls: [URL]) async {
        isImportingNotes = true
        defer { isImportingNotes = false }
        do {
            noteImportMessage = NoteImportMessage.text(for: try await library.importNotes(from: urls))
        } catch {
            noteImportMessage = "couldn't import the notes. try again."
        }
        await refresh()
    }

    /// Opens the composer for a new typed thought.
    public func startComposing() async {
        await saveIfNeeded()
        composedID = nil
        composedSavedText = ""
        composerText = ""
        isComposing = true
        if let capture, !capture.isRecording { await capture.toggle() }
    }

    /// You started typing: writing takes over, so the recording is thrown away (as with tälli).
    public func typingStarted() async {
        guard let capture, capture.isRecording, !composerText.isEmpty else { return }
        await capture.cancel()
    }

    /// Esc: throws a running recording away, keeps anything typed, and closes the composer.
    public func closeComposer() async {
        if let capture, capture.isRecording { await capture.cancel() }
        await finishComposing()
    }

    /// Saves the composer's text: the first save creates the thought, later saves update it.
    public func saveComposerIfNeeded() async {
        composerAutosaveTask?.cancel()
        let text = composerText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text != composedSavedText else { return }
        do {
            if let id = composedID {
                try await library.saveText(id: id, text: text)
            } else {
                composedID = try await library.createThought(text: text).id
            }
            composedSavedText = text
        } catch {
            errorMessage = "couldn't save the thought. your text is still here, so try again."
        }
    }

    /// ⌘↩: saves what you said (a spoken thought) or wrote (a typed thought), closes the composer and opens
    /// the new thought. Nothing is created if nothing was said or written.
    public func finishComposing() async {
        if let capture, capture.isRecording {
            let savedBefore = capture.lastSavedAt
            await capture.toggle()
            isComposing = false
            showsTrash = false
            await refresh()
            if capture.lastSavedAt != savedBefore, let id = capture.lastSavedEntryID { await select(id) }
            return
        }
        await saveComposerIfNeeded()
        isComposing = false
        let id = composedID
        composedID = nil
        showsTrash = false
        await refresh()
        if let id { await select(id) }
    }

    private func scheduleComposerAutosave() {
        guard isComposing else { return }
        composerAutosaveTask?.cancel()
        let delay = autosaveDelay
        composerAutosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.saveComposerIfNeeded()
        }
    }

    /// Thoughts matching a palette search: those with the words first, then related ones.
    public func findThoughts(_ text: String, limit: Int) async -> [SearchHit] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Array(((try? await library.search(EntryQuery(text: text))) ?? []).prefix(limit))
    }

    /// Whether the current search found this thought only by meaning.
    public func isRelated(_ id: String) -> Bool {
        !query.words.isEmpty && matches[id]?.match == .related
    }

    /// What to highlight in a thought's text as it is now: the search words wherever they occur, and for a
    /// related thought the passage that matched. The search is the window's own, or else the one the thought
    /// was opened from (⌘K). Recomputed from the text, so highlights follow your typing; they are only drawn,
    /// never saved.
    public func highlights(in text: String, entryID: String) -> [TextHighlight] {
        var highlights = conceptHighlights(in: text, entryID: entryID)
        guard let search = search(for: entryID) else { return highlights }
        if let hit = search.hit, hit.match == .related, let passage = hit.passage,
            let range = Self.locate(passage, of: hit.entry.text, in: text)
        {
            highlights.append(TextHighlight(range: range, kind: .passage))
        }
        highlights += TextMatch.sections(for: search.words, in: text).map { TextHighlight(range: $0, kind: .word) }
        return highlights
    }

    /// Changes whenever the thought or the search it is shown with changes; the editor then scrolls to the first
    /// highlight.
    public func highlightKey(for entryID: String) -> String {
        entryID + "|" + (search(for: entryID)?.text ?? "")
    }

    /// Opens a search result and keeps showing what was searched for in it, e.g. after choosing it in ⌘K.
    /// Goes to a search result in the view you're in, with what was searched for kept marked in it (⌘K):
    /// flow scrolls to it, stack opens its folder (or the loose thoughts) and the thought, time moves to its
    /// day, space opens its first concept (or flow, when it has none).
    public func open(_ hit: SearchHit, searchedFor text: String) async {
        switch view {
        case .flow:
            await goInFlow(to: hit.id)
        case .stack:
            let inGroup = (try? await library.thoughtIDs(in: stackGroup)) ?? []
            if !inGroup.contains(hit.id) {
                let folder = try? await library.folderID(of: hit.id)
                stackGroup = folder.map(StackGroup.folder) ?? .loose
                await refresh()
            }
            await select(hit.id)
            scrollRequest = ScrollRequest(entryID: hit.id)
        case .time:
            timeRange = TimelineRange(zoom: timeRange.zoom, anchor: hit.entry.createdAt)
            await refresh()
            await select(hit.id)
        case .space:
            if let concept = (try? await library.meaning(id: hit.id))?.concepts.first {
                await openConcept(concept.id)
            } else {
                await goInFlow(to: hit.id)
            }
        }
        openedSearch = OpenedSearch(text: text, hit: hit)
    }

    /// flow, scrolled to a thought; a filter that hides it is dropped.
    private func goInFlow(to id: String) async {
        if view != .flow { await show(view: .flow) }
        if !flowEntries.contains(where: { $0.id == id }) {
            query.period = .all
            query.sources = nil
            await refresh()
        }
        await select(id)
        scrollRequest = ScrollRequest(entryID: id)
    }

    /// The search that applies to a thought: the window's search field, or the search it was opened from.
    private func search(for entryID: String) -> (text: String, words: [String], hit: SearchHit?)? {
        if !query.words.isEmpty { return (query.text, query.words, matches[entryID]) }
        guard let opened = openedSearch, opened.hit.id == entryID else { return nil }
        return (opened.text, EntryQuery(text: opened.text).words, opened.hit)
    }

    /// Concept words, as analysed. Only while the text is still the one that was analysed: after an edit
    /// the positions would be wrong, and the thought is analysed again shortly anyway.
    private func conceptHighlights(in text: String, entryID: String) -> [TextHighlight] {
        guard let meaning = meanings[entryID], entries.first(where: { $0.id == entryID })?.text == text else {
            return []
        }
        let length = text.utf16.count
        return meaning.concepts.flatMap { concept in
            concept.utf16Ranges.filter { $0.upperBound <= length }.map {
                TextHighlight(range: $0, kind: .concept(concept.kind))
            }
        }
        .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Where the passage from the searched text now is in the edited text, if it is still there unchanged.
    private static func locate(_ passage: Range<Int>, of original: String, in text: String) -> Range<Int>? {
        let units = Array(original.utf16)
        guard passage.lowerBound >= 0, passage.upperBound <= units.count else { return nil }
        let passageText = String(decoding: units[passage], as: UTF16.self)
        if original == text { return passage }
        let found = (text as NSString).range(of: passageText)
        return found.location == NSNotFound ? nil : found.location..<(found.location + found.length)
    }

    /// Saves a thought edited in place in the flow.
    public func saveFlowText(id: String, text: String) async {
        do {
            try await library.saveText(id: id, text: text)
            if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].text = text }
        } catch {
            errorMessage = "couldn't save the thought. your text is still here, so try again."
        }
    }

    /// The flow's thoughts, newest first (issue #53).
    public var flowEntries: [Entry] { entries }

    // MARK: The bar at the bottom and the month rail

    /// What the bar at the bottom holds right now.
    public var bar: ExploreBar {
        if showsTrash { return .trash }
        switch view {
        case .stack, .flow: return .thoughts
        case .time: return .time
        case .space: return .space
        }
    }

    /// flow and time have the month rail at the side.
    public var showsMonthRail: Bool { !showsTrash && (view == .flow || view == .time) }

    /// The one Source shown, or nil while both are.
    public var onlySource: EntrySource? {
        guard let sources = query.sources, sources.count == 1 else { return nil }
        return sources.first
    }

    public func choose(period: EntryQuery.Period) async {
        query.period = period
        await select(nil)
        await refresh()
    }

    /// Shows only this Source; asking again shows both.
    public func toggle(source: EntrySource) async {
        query.sources = onlySource == source ? nil : [source]
        await refresh()
    }

    public func leaveTrash() async {
        await show(trash: false)
    }

    /// Deletes every thought in trash for good (each goes on to the macOS Trash).
    public func emptyTrash() async {
        var failed = false
        for item in trashedEntries {
            do {
                try await library.deleteForever(trashedFolder: item.trashedFolder)
            } catch {
                failed = true
            }
        }
        if failed { errorMessage = "couldn't empty the trash. try again." }
        await refresh()
    }

    public var railMonths: [RailMonth] { MonthRail.months(for: entries, calendar: .current) }

    /// In time: the month the span ends in, marked on the rail.
    public var currentRailMonth: Date? {
        guard view == .time else { return nil }
        return MonthRail.startOfMonth(timeRange.end.addingTimeInterval(-1), calendar: .current)
    }

    /// flow scrolls to the month's newest thought; time shows the whole month.
    public func jump(to month: RailMonth) async {
        if view == .time {
            timeRange.show(monthStarting: month.start)
            return
        }
        let next = Calendar.current.date(byAdding: .month, value: 1, to: month.start) ?? month.start
        guard let newest = flowEntries.first(where: { $0.createdAt >= month.start && $0.createdAt < next }) else {
            return
        }
        scrollRequest = ScrollRequest(entryID: newest.id)
    }

    /// time: back to today, at the same zoom.
    public func showToday() {
        timeRange.jump(to: Date())
    }

    // MARK: Picking concepts in space

    /// The concepts space shows: of the chosen kind, matching the search, most-mentioned first.
    public var visibleConcepts: [ConceptSummary] {
        let search = conceptSearch.trimmingCharacters(in: .whitespaces)
        return concepts.filter { concept in
            (conceptKindFilter.map { concept.kind == $0 } ?? true)
                && (search.isEmpty || concept.name.localizedStandardContains(search))
        }
    }

    /// Thoughts that mention every picked concept and match the Source toggles, newest first.
    public var pickedThoughts: [Entry] {
        guard let first = pickedConcepts.first, let base = pickedDetails[first] else { return [] }
        let others = pickedConcepts.dropFirst().compactMap { pickedDetails[$0].map { Set($0.thoughts.map(\.id)) } }
        return base.thoughts
            .filter { entry in
                others.allSatisfy { $0.contains(entry.id) } && (query.sources?.contains(entry.source) ?? true)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Adds a concept to the filter, or takes it away when it is already picked.
    public func togglePick(_ id: String) async {
        if pickedConcepts.contains(id) {
            pickedConcepts.removeAll { $0 == id }
            pickedDetails[id] = nil
        } else {
            let generation = pickGeneration
            do {
                let detail = try await library.conceptDetail(id: id)
                // A second click while loading, or a clear meanwhile, wins.
                guard generation == pickGeneration, !pickedConcepts.contains(id) else { return }
                pickedDetails[id] = detail
                pickedConcepts.append(id)
            } catch {
                errorMessage = "couldn't open that concept. try again."
            }
        }
        conceptDetail = pickedConcepts.last.flatMap { pickedDetails[$0] }
    }

    public func clearPicks() {
        pickGeneration += 1
        pickedConcepts = []
        pickedDetails = [:]
        conceptDetail = nil
    }

    /// Switching views keeps the open thought; leaving trash or opening stack with nothing open shows the newest.
    private func show(view: ExploreViewKind) async {
        self.view = view
        if showsTrash {
            await show(trash: false)
        } else {
            await refresh()
        }
        await openNewestIfNothingOpen()
    }

    /// stack always shows a thought: with nothing chosen, the newest one opens.
    func openNewestIfNothingOpen() async {
        guard view == .stack, !showsTrash, selectedID == nil, let newest = entries.first else { return }
        await select(newest.id)
    }

    private func jumpMatch(by step: Int) {
        guard !flowMatches.isEmpty else { return }
        let index = currentMatch.flatMap { flowMatches.firstIndex(of: $0) } ?? -step
        let next = ((index + step) % flowMatches.count + flowMatches.count) % flowMatches.count
        currentMatch = flowMatches[next]
    }

    private func updateMatches() {
        flowMatches = flowEntries.filter { matches[$0.id]?.match == .words }.map(\.id)
        if currentMatch.map({ !flowMatches.contains($0) }) ?? true { currentMatch = flowMatches.first }
    }

    private func show(trash: Bool) async {
        showsTrash = trash
        await select(nil)
        await refresh()
    }

    public func refresh() async {
        // Searches can finish out of order (the first one may load a model, the Archive may change meanwhile);
        // only the newest refresh may change what the window shows.
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
            // The count in the bar may fail on its own; your thoughts still show.
            if !showsTrash, let count = try? await library.trashedCount(), generation == refreshGeneration {
                trashCount = count
            }
            if showsTrash {
                let trashed = try await library.trashed()
                guard generation == refreshGeneration else { return }
                trashedEntries = trashed
                trashCount = trashed.count
            } else if view == .space {
                // space lists concepts (loaded below); it shows no thoughts of its own.
            } else if view == .stack {
                let asked = query
                let index = try await library.stackIndex()
                var group = stackGroup
                // A folder or concept that is gone (deleted, merged) falls back to the loose thoughts.
                if case .folder(let id) = group, !index.folders.contains(where: { $0.id == id }) { group = .loose }
                if case .concept(let id) = group, !index.concepts.contains(where: { $0.id == id }) { group = .loose }
                let inGroup = try await library.thoughtIDs(in: group)
                let found = try await library.search(asked).filter { inGroup.contains($0.id) }
                guard generation == refreshGeneration else { return }
                stackIndex = index
                stackGroup = group
                entries = found.map(\.entry)
                matches =
                    asked.words.isEmpty ? [:] : Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            } else {
                // flow and time show everything the filters allow; in flow the search highlights instead.
                var unfiltered = query
                unfiltered.text = ""
                if view == .time { unfiltered.period = .all }
                let asked = query
                let shown = try await library.search(unfiltered).map(\.entry)
                let found = view == .flow && !asked.words.isEmpty ? try await library.search(asked) : []
                guard generation == refreshGeneration else { return }
                entries = shown
                matches = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                updateMatches()
            }
            await reloadMeaning(generation: generation)
        } catch {
            guard generation == refreshGeneration else { return }
            errorMessage = "couldn't load your thoughts. try again."
        }
    }

    /// Loads a thought's summary, concepts and related thoughts, once; Archive changes reload them.
    public func loadMeaning(for id: String) async {
        visibleMeanings.insert(id)
        guard meanings[id] == nil, let meaning = try? await library.meaning(id: id) else { return }
        meanings[id] = meaning
    }

    /// Opens a concept in space, picked on its own: its thoughts and the concepts that appear with it.
    public func openConcept(_ id: String) async {
        if view != .space { await show(view: .space) }
        clearPicks()
        await togglePick(id)
    }

    /// Shows a thought in flow, scrolled to it (from space, or a related thought).
    public func reveal(_ id: String) async {
        if view != .flow { await show(view: .flow) }
        scrollRequest = ScrollRequest(entryID: id)
    }

    /// A thought scrolled out of flow: its meaning is dropped, so refreshes only reload what is on screen.
    /// A thought scrolled out of view: its meaning is kept (scrolling back costs nothing), but it is no longer
    /// reloaded on every Archive change; after one it is loaded again when it comes back.
    public func forgetMeaning(for id: String) {
        visibleMeanings.remove(id)
    }

    public func saveSummary(_ text: String?, for id: String) async {
        do {
            try await library.saveSummary(id: id, text: text)
            meanings[id] = try await library.meaning(id: id)
        } catch {
            errorMessage = "couldn't save the summary. try again."
        }
    }

    private func reloadMeaning(generation: Int) async {
        // Off-screen ones may be out of date now: dropped, and loaded again when they come back.
        for id in meanings.keys where !visibleMeanings.contains(id) { meanings[id] = nil }
        for id in visibleMeanings {
            let meaning = try? await library.meaning(id: id)
            guard generation == refreshGeneration else { return }
            if let meaning { meanings[id] = meaning }
        }
        guard view == .space, let concepts = try? await library.concepts(), generation == refreshGeneration
        else { return }
        self.concepts = concepts
        // A picked concept that is gone (e.g. its only thought went to trash) is no longer picked.
        let existing = Set(concepts.map(\.id))
        pickedConcepts.removeAll { !existing.contains($0) }
        pickedDetails = pickedDetails.filter { existing.contains($0.key) }
        for id in pickedConcepts {
            let detail = try? await library.conceptDetail(id: id)
            guard generation == refreshGeneration else { return }
            if let detail, pickedConcepts.contains(id) { pickedDetails[id] = detail }
        }
        conceptDetail = pickedConcepts.last.flatMap { pickedDetails[$0] }
    }

    /// The thought you clicked: selected at once, while its text loads (the list reads this, not `detail`,
    /// so the highlighted row never jumps back and forth).
    public private(set) var selectedID: String?

    /// A click in the list.
    public func choose(_ id: String?) {
        selectedID = id
        Task { await select(id) }
    }

    /// ↑/↓ in the list: the previous or next thought, staying within the list.
    public func moveSelection(by step: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedID.flatMap { id in entries.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + step, 0), entries.count - 1) } ?? (step > 0 ? 0 : entries.count - 1)
        choose(entries[next].id)
    }

    public func select(_ id: String?) async {
        selectedID = id
        openedSearch = nil
        await saveIfNeeded()
        guard let id else {
            setDetail(nil)
            return
        }
        do {
            let loaded = try await library.detail(id: id)
            // Clicked another thought meanwhile: that one wins.
            guard selectedID == id else { return }
            setDetail(loaded)
        } catch {
            errorMessage = "couldn't open the thought. try again."
        }
    }

    /// Saves the editor's Text if it differs from what is stored.
    public func saveIfNeeded() async {
        autosaveTask?.cancel()
        guard let id = detail?.entry.id, editorText != savedText else { return }
        let text = editorText
        do {
            try await library.saveText(id: id, text: text)
            savedText = text
        } catch {
            errorMessage = "couldn't save the thought. your text is still here, so try again."
        }
    }

    /// Only imported thoughts: a spoken or typed thought's date is when you said or wrote it.
    public var canChangeDate: Bool { detail?.entry.source.isImported ?? false }

    /// Gives the open imported thought the date you wrote it.
    public func changeDate(to date: Date) async {
        guard let id = detail?.entry.id else { return }
        await changeDate(of: id, to: date)
    }

    /// Gives an imported thought (open, or in flow) the date you wrote it. Other thoughts keep theirs.
    public func changeDate(of id: String, to date: Date) async {
        let source = detail?.entry.id == id ? detail?.entry.source : entries.first { $0.id == id }?.source
        guard source?.isImported == true else { return }
        if detail?.entry.id == id { await saveIfNeeded() }
        do {
            try await library.setDate(id: id, to: date)
            if var changed = detail, changed.entry.id == id {
                changed.entry = try await library.detail(id: id).entry
                detail = changed
            }
            await refresh()
        } catch {
            errorMessage = "couldn't change the date. try again."
        }
    }

    public func trashSelected() async {
        guard let id = detail?.entry.id else { return }
        await trash(id)
    }

    /// Moves a thought to trash (undo brings it back); in stack the next newest one opens.
    public func trash(_ id: String) async {
        await saveIfNeeded()
        do {
            lastTrashed = try await library.trash(id: id)
            if selectedID == id { setDetail(nil) }
            // Gone from the list at once, so it is never picked as the next one to open.
            entries.removeAll { $0.id == id }
            await refresh()
            entries.removeAll { $0.id == id }
            await openNewestIfNothingOpen()
        } catch {
            errorMessage = "couldn't move the thought to trash. try again."
        }
    }

    public func undoTrash() async {
        guard let folder = lastTrashed else { return }
        lastTrashed = nil
        try? await library.restore(trashedFolder: folder)
        await refresh()
    }

    public func restore(_ item: TrashedEntry) async {
        try? await library.restore(trashedFolder: item.trashedFolder)
        await refresh()
    }

    public func deleteForever(_ item: TrashedEntry) async {
        try? await library.deleteForever(trashedFolder: item.trashedFolder)
        await refresh()
    }

    private func setDetail(_ newDetail: EntryDetail?) {
        autosaveTask?.cancel()
        detail = newDetail
        selectedID = newDetail?.entry.id
        savedText = newDetail?.entry.text ?? ""
        editorText = savedText
        autosaveTask?.cancel()
    }

    private func scheduleAutosave() {
        guard detail != nil, editorText != savedText else { return }
        autosaveTask?.cancel()
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.saveIfNeeded()
        }
    }
}
