import Domain
import SwiftUI

extension Hotkey {
    /// The SwiftUI shortcut for an in-app command, or nil for keys SwiftUI cannot express (F-keys).
    var keyboardShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        switch self.key {
        case .space: key = .space
        case .escape: key = .escape
        case .enter: key = .return
        case .delete: key = .delete
        case .left: key = .leftArrow
        case .right: key = .rightArrow
        case .up: key = .upArrow
        case .down: key = .downArrow
        case .equal: key = "="
        case .minus: key = "-"
        case .letter(let letter): key = KeyEquivalent(letter)
        case .digit(let digit): key = KeyEquivalent(Character(String(digit)))
        case .function: return nil
        }
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}

/// Invisible buttons that give every command its configured shortcut inside a window.
struct CommandShortcutButtons: View {
    var model: ExploreViewModel

    var body: some View {
        ZStack {
            ForEach(Commands.all, id: \.self) { command in
                if let shortcut = model.shortcuts[command]?.keyboardShortcut {
                    Button(command.title) { Task { await model.perform(command) } }
                        .keyboardShortcut(shortcut)
                }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
