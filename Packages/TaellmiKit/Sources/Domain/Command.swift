import Foundation

/// Every action in tällmi that can be run from the keyboard or the ⌘K palette. The ids are fixed;
/// the shortcuts live in config (`shortcut.<id>`), so they can be changed without code.
public enum Command: String, Sendable, CaseIterable, Hashable {
    case openPalette = "palette.open"
    case newThought = "thought.new"
    case deleteThought = "thought.delete"
    case searchThoughts = "search.focus"
    case showStack = "view.stack"
    case showTrash = "trash.show"
    case playRecording = "recording.toggle"

    public var id: String { rawValue }

    /// The words users see (brand book: lowercase, verb + object).
    public var title: String {
        switch self {
        case .openPalette: "search or run a command"
        case .newThought: "new thought"
        case .deleteThought: "delete thought"
        case .searchThoughts: "search thoughts"
        case .showStack: "show stack"
        case .showTrash: "show trash"
        case .playRecording: "play or pause recording"
        }
    }

    /// The setting that holds this command's shortcut.
    public var settingKey: String { "shortcut.\(rawValue)" }
}

public enum Commands {
    public static let all = Command.allCases
}
