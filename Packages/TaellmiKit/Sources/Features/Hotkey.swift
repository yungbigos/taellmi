import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut, parsed from the `capture.hotkey` setting (e.g. "option+command+space").
nonisolated public struct Hotkey: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        case space
        case letter(Character)
    }

    public struct Modifiers: OptionSet, Sendable, Equatable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public enum ParseError: Error, Equatable {
        case invalid(String)
    }

    public var key: Key
    public var modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public init(parsing text: String) throws {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let last = parts.last else { throw ParseError.invalid(text) }
        var modifiers: Modifiers = []
        for part in parts.dropLast() {
            switch part {
            case "command", "cmd": modifiers.insert(.command)
            case "option", "alt": modifiers.insert(.option)
            case "control", "ctrl": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default: throw ParseError.invalid(text)
            }
        }
        switch last {
        case "space": key = .space
        case let letter where letter.count == 1 && Self.letterCodes[letter.first ?? " "] != nil:
            key = .letter(letter.first ?? " ")
        default: throw ParseError.invalid(text)
        }
        self.modifiers = modifiers
    }

    /// Carbon virtual key code.
    var keyCode: UInt32 {
        switch key {
        case .space: UInt32(kVK_Space)
        case .letter(let character): UInt32(Self.letterCodes[character] ?? kVK_Space)
        }
    }

    /// Carbon modifier mask.
    var carbonModifiers: UInt32 {
        var mask = 0
        if modifiers.contains(.command) { mask |= cmdKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        return UInt32(mask)
    }

    private static let letterCodes: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    ]
}
