import Domain
import Foundation
import Observation

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

/// What the Explore window needs from the Archive. Implemented in the composition root.
public protocol ExploreLibrary: Sendable {
    func search(_ query: EntryQuery) async throws -> [Entry]
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
    func deleteForever(trashedFolder: String) async throws
}

/// State and actions of the Explore window.
@Observable
public final class ExploreViewModel {
    public var query = EntryQuery()
    public var showsTrash = false
    /// Current shortcut of every command, from config.
    public var shortcuts: [Command: Hotkey] = [:]
    public var isPaletteOpen = false
    /// Bumped when the search field should take focus / the recording should play or pause.
    public private(set) var searchFocusRequest = 0
    public private(set) var playbackRequest = 0
    /// Writing a new thought in the full-window composer.
    public private(set) var isComposing = false
    public var composerText = "" {
        didSet { scheduleComposerAutosave() }
    }
    @ObservationIgnored private var composedID: String?
    @ObservationIgnored private var composedSavedText = ""
    @ObservationIgnored private var composerAutosaveTask: Task<Void, Never>?
    public private(set) var entries: [Entry] = []
    public private(set) var trashedEntries: [TrashedEntry] = []
    public private(set) var detail: EntryDetail?
    public private(set) var errorMessage: String?
    /// The Text being edited; saved automatically shortly after you stop typing.
    public var editorText = "" {
        didSet { scheduleAutosave() }
    }

    @ObservationIgnored private let library: any ExploreLibrary
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var savedText = ""
    @ObservationIgnored private var lastTrashed: String?
    @ObservationIgnored private var observation: Task<Void, Never>?

    /// - Parameter autosaveDelay: pause after the last keystroke before saving (from config).
    public init(library: any ExploreLibrary, autosaveDelay: Duration) {
        self.library = library
        self.autosaveDelay = autosaveDelay
    }

    /// Re-runs the search (or reloads the Trash) whenever the Archive changes.
    public func startObserving() {
        observation?.cancel()
        let changes = library.changes()
        observation = Task { [weak self] in
            for await _ in changes { await self?.refresh() }
        }
    }

    /// Runs a command (from its shortcut or the ⌘K palette).
    public func perform(_ command: Command) async {
        switch command {
        case .openPalette: isPaletteOpen = true
        case .newThought: await startComposing()
        case .deleteThought: await trashSelected()
        case .searchThoughts:
            if showsTrash { await show(trash: false) }
            searchFocusRequest += 1
        case .showStack: await show(trash: false)
        case .showTrash: await show(trash: true)
        case .playRecording: playbackRequest += 1
        }
    }

    /// Opens the composer for a new typed thought.
    public func startComposing() async {
        await saveIfNeeded()
        composedID = nil
        composedSavedText = ""
        composerText = ""
        isComposing = true
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

    /// ⌘↩ or esc: saves, closes the composer and opens the new thought (nothing is created if it is empty).
    public func finishComposing() async {
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

    /// Thoughts matching a palette search, newest first.
    public func findThoughts(_ text: String, limit: Int) async -> [Entry] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Array(((try? await library.search(EntryQuery(text: text))) ?? []).prefix(limit))
    }

    private func show(trash: Bool) async {
        showsTrash = trash
        await select(nil)
        await refresh()
    }

    public func refresh() async {
        do {
            if showsTrash {
                trashedEntries = try await library.trashed()
            } else {
                entries = try await library.search(query)
            }
        } catch {
            errorMessage = "couldn't load your thoughts. try again."
        }
    }

    public func select(_ id: String?) async {
        await saveIfNeeded()
        guard let id else {
            setDetail(nil)
            return
        }
        do {
            setDetail(try await library.detail(id: id))
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

    public func trashSelected() async {
        guard let id = detail?.entry.id else { return }
        await saveIfNeeded()
        do {
            lastTrashed = try await library.trash(id: id)
            setDetail(nil)
            await refresh()
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
