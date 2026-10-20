import Foundation

/// Every action in tällmi that can be run from the keyboard or the ⌘K palette. The ids are fixed;
/// the shortcuts live in config (`shortcut.<id>`), so they can be changed without code.
public enum Command: String, Sendable, CaseIterable, Hashable {
    case openPalette = "palette.open"
    case newThought = "thought.new"
    case deleteThought = "thought.delete"
    case searchThoughts = "search.focus"
    case showStack = "view.stack"
    case showFlow = "view.flow"
    case showTime = "view.time"
    case showSpace = "view.space"
    case nextMatch = "match.next"
    case previousMatch = "match.previous"
    case zoomInTime = "time.zoom_in"
    case zoomOutTime = "time.zoom_out"
    case showEarlier = "time.earlier"
    case showLater = "time.later"
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
        case .showFlow: "show flow"
        case .showTime: "show time"
        case .showSpace: "show space"
        case .nextMatch: "next match"
        case .previousMatch: "previous match"
        case .zoomInTime: "zoom in on time"
        case .zoomOutTime: "zoom out of time"
        case .showEarlier: "show earlier"
        case .showLater: "show later"
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
