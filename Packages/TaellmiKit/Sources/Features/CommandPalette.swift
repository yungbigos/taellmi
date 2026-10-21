import Domain
import Foundation
import Observation

/// One line of a search result: the part of the thought around the match on one line, with ellipses where
/// text was left out, and where the search words are in it. Computed once when results arrive.
nonisolated public struct ResultSnippet: Sendable, Equatable {
    public let text: String
    /// UTF-16 ranges of the search words in `text`.
    public let ranges: [Range<Int>]

    public init(hit: SearchHit, maxLength: Int) {
        let snippet = Snippet(of: hit.entry.text, around: hit.wordRanges.first ?? hit.passage, maxLength: maxLength)
        let lead = snippet.cutsStart ? "…" : ""
        let shift = lead.utf16.count
        text = lead + snippet.text.replacingOccurrences(of: "\n", with: " ") + (snippet.cutsEnd ? "…" : "")
        ranges = snippet.ranges(hit.wordRanges).map { ($0.lowerBound + shift)..<($0.upperBound + shift) }
    }
}

/// One row in the ⌘K palette: a command or a thought.
nonisolated public struct PaletteItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case command(Command)
        case thought(String)
    }

    public var kind: Kind
    public var title: String
    public var shortcut: String?
    /// For a thought: where the search words are in `title` (UTF-16 ranges).
    public var highlights: [Range<Int>] = []
    /// For a thought found only by meaning.
    public var isRelated = false
    public var id: String {
        switch kind {
        case .command(let command): "command:\(command.id)"
        case .thought(let id): "thought:\(id)"
        }
    }
}

/// ⌘K: one field that finds commands and thoughts.
@Observable
public final class CommandPaletteModel {
    public private(set) var results: [PaletteItem] = []
    public private(set) var highlighted = 0
    public var query = ""

    @ObservationIgnored private let explore: ExploreViewModel
    /// The thoughts found for the current text, so choosing one opens it with what was searched for.
    @ObservationIgnored private var hits: [String: SearchHit] = [:]
    @ObservationIgnored private let thoughtLimit: Int

    public init(explore: ExploreViewModel, thoughtLimit: Int = 8) {
        self.explore = explore
        self.thoughtLimit = thoughtLimit
    }

    public var isPresented: Bool {
        get { explore.isPaletteOpen }
        set { explore.isPaletteOpen = newValue }
    }

    public func update(query text: String) async {
        query = text
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        // Formats are offered only while a thought was being edited as ⌘K opened (ADR 0014).
        let canFormat = explore.formatting.canFormatFromPalette
        let commands = Commands.all
            .filter { command in (canFormat || !command.isFormatting) && words.allSatisfy { command.title.contains($0) }
            }
            .map { PaletteItem(kind: .command($0), title: $0.title, shortcut: explore.shortcuts[$0]?.displayLabel) }
        let found = await explore.findThoughts(text, limit: thoughtLimit)
        let thoughts = found.map(Self.item)
        // Searches can finish out of order (one may first load a model); only the latest typing counts.
        guard query == text else { return }
        hits = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        results = commands + thoughts
        highlighted = 0
    }

    public func moveHighlight(by delta: Int) {
        guard !results.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), results.count - 1)
    }

    public func chooseHighlighted() async {
        guard results.indices.contains(highlighted) else { return }
        await choose(results[highlighted])
    }

    public func choose(_ item: PaletteItem) async {
        isPresented = false
        switch item.kind {
        case .command(let command): await explore.perform(command)
        case .thought(let id):
            if explore.showsTrash { await explore.perform(.showStack) }
            if let hit = hits[id] {
                await explore.open(hit, searchedFor: query)
            } else {
                await explore.select(id)
            }
        }
    }

    private nonisolated static let snippetLength = 90

    /// A thought row: the part of the text around the match, with the search words marked.
    private nonisolated static func item(_ hit: SearchHit) -> PaletteItem {
        let snippet = ResultSnippet(hit: hit, maxLength: snippetLength)
        return PaletteItem(
            kind: .thought(hit.id), title: snippet.text, shortcut: nil, highlights: snippet.ranges,
            isRelated: hit.match == .related)
    }
}

/// A shortcut clashes when another command already uses it.
nonisolated public struct CommandShortcutChecker: HotkeyConflictChecking {
    private let shortcuts: @Sendable () -> [Command: Hotkey]
    private let ignoring: Command?

    public init(shortcuts: [Command: Hotkey], ignoring: Command?) {
        self.init(current: { shortcuts }, ignoring: ignoring)
    }

    /// Reads the current shortcuts on every check, so it never works from a stale copy.
    public init(current: @escaping @Sendable () -> [Command: Hotkey], ignoring: Command?) {
        self.shortcuts = current
        self.ignoring = ignoring
    }

    public func conflict(for hotkey: Hotkey) -> String? {
        shortcuts().first { $0.key != ignoring && $0.value == hotkey }.map { "\"\($0.key.title)\"" }
    }
}

/// Asks several checkers in turn (e.g. macOS shortcuts, then other commands).
nonisolated public struct CombinedConflictChecker: HotkeyConflictChecking {
    private let checkers: [any HotkeyConflictChecking]

    public init(_ checkers: [any HotkeyConflictChecking]) {
        self.checkers = checkers
    }

    public func conflict(for hotkey: Hotkey) -> String? {
        checkers.lazy.compactMap { $0.conflict(for: hotkey) }.first
    }
}
