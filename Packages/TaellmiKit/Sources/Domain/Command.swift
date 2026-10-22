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
    case importNotes = "notes.import"
    case importWhatsApp = "whatsapp.import"
    case formatBold = "format.bold"
    case formatItalic = "format.italic"
    case formatUnderline = "format.underline"
    case formatStrikethrough = "format.strikethrough"
    case formatBulletList = "format.bullet_list"
    case formatNumberedList = "format.numbered_list"
    case indentListItem = "format.indent"
    case outdentListItem = "format.outdent"

    public var id: String { rawValue }

    /// The words users see (brand book: lowercase, verb + object; formats are named, since they switch on
    /// and off).
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
        case .importNotes: "import from apple notes …"
        case .importWhatsApp: "import from whatsapp …"
        case .formatBold: "bold"
        case .formatItalic: "italic"
        case .formatUnderline: "underline"
        case .formatStrikethrough: "strike through"
        case .formatBulletList: "bullet list"
        case .formatNumberedList: "numbered list"
        case .indentListItem: "indent list item"
        case .outdentListItem: "outdent list item"
        }
    }

    /// The format this command switches, if it is one (ADR 0014).
    public var format: Format? {
        switch self {
        case .formatBold: .bold
        case .formatItalic: .italic
        case .formatUnderline: .underline
        case .formatStrikethrough: .strikethrough
        case .formatBulletList: .bulletList
        case .formatNumberedList: .numberedList
        default: nil
        }
    }

    /// Formatting commands act on the thought you are typing in, so only the editor handles their keys.
    public var isFormatting: Bool { format != nil || self == .indentListItem || self == .outdentListItem }

    /// The setting that holds this command's shortcut.
    public var settingKey: String { "shortcut.\(rawValue)" }
}

public enum Commands {
    public static let all = Command.allCases
}
