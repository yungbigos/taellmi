import Domain
import Foundation
import Observation

/// One row in the ⌘K palette: a command or a thought.
nonisolated public struct PaletteItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case command(Command)
        case thought(String)
    }

    public var kind: Kind
    public var title: String
    public var shortcut: String?
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
        let commands = Commands.all
            .filter { command in words.allSatisfy { command.title.contains($0) } }
            .map { PaletteItem(kind: .command($0), title: $0.title, shortcut: explore.shortcuts[$0]?.displayLabel) }
        let thoughts = await explore.findThoughts(text, limit: thoughtLimit).map {
            PaletteItem(kind: .thought($0.id), title: Self.firstLine(of: $0.text), shortcut: nil)
        }
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
            await explore.select(id)
        }
    }

    private nonisolated static func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        return line.count > 90 ? String(line.prefix(90)) + "…" : line
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
