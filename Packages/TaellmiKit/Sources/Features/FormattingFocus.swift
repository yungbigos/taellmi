import Domain

/// What a formatting command does to the thought being edited (ADR 0014).
public enum FormattingAction: Sendable, Equatable {
    case toggle(Format)
    case indent
    case outdent
}

extension Command {
    /// The formatting this command applies, if it is a formatting command.
    public var formattingAction: FormattingAction? {
        if let format { return .toggle(format) }
        switch self {
        case .indentListItem: return .indent
        case .outdentListItem: return .outdent
        default: return nil
        }
    }
}

/// A thought editor that formatting can be applied to.
@MainActor
public protocol FormattingTarget: AnyObject {
    func applyFormatting(_ action: FormattingAction)
}

/// Which thought editor formatting from ⌘K goes to. Shortcuts and the floating bar are handled by the editor
/// you type in; ⌘K takes the keyboard away from it, so the editor is remembered as ⌘K opens.
@MainActor
public final class FormattingFocus {
    private weak var focused: (any FormattingTarget)?
    private weak var paletteTarget: (any FormattingTarget)?

    public init() {}

    public func editorDidFocus(_ editor: any FormattingTarget) {
        focused = editor
    }

    public func editorDidBlur(_ editor: any FormattingTarget) {
        if focused === editor { focused = nil }
    }

    /// Called as ⌘K opens, while the editor still has the keyboard.
    func paletteWillOpen() {
        paletteTarget = focused
    }

    /// Whether ⌘K should offer the formats: a thought was being edited when it opened.
    var canFormatFromPalette: Bool { paletteTarget != nil }

    func applyFromPalette(_ action: FormattingAction) {
        paletteTarget?.applyFormatting(action)
        paletteTarget = nil
    }
}
