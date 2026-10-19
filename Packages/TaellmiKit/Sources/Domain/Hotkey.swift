import Foundation

/// A global keyboard shortcut, stored in the `capture.hotkey` setting as text (e.g. "option+command+space").
/// Key codes and modifier masks are macOS virtual key codes / Carbon masks, kept as plain numbers here.
public struct Hotkey: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        case space
        case escape
        case letter(Character)
        case digit(Int)
        case function(Int)
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

    /// Esc without modifiers: registered only while tälli is open, to cancel.
    public static let escape = Hotkey(key: .escape, modifiers: [])

    public init(key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Parses the setting text. At least one modifier is required.
    public init(parsing text: String) throws {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let last = parts.last, let key = Self.key(named: last) else {
            throw ParseError.invalid(text)
        }
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
        self.init(key: key, modifiers: modifiers)
    }

    /// From a key press. Needs Control, Option or Command; Shift alone is not enough.
    public init?(keyCode: Int, command: Bool, option: Bool, control: Bool, shift: Bool) {
        guard command || option || control, let key = Self.keysByCode[keyCode] else { return nil }
        var modifiers: Modifiers = []
        if command { modifiers.insert(.command) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        if shift { modifiers.insert(.shift) }
        self.init(key: key, modifiers: modifiers)
    }

    /// The text stored in the setting.
    public var settingValue: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("control") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.command) { parts.append("command") }
        if modifiers.contains(.shift) { parts.append("shift") }
        return (parts + [keyName]).joined(separator: "+")
    }

    /// "⌃⌥⌘T", "⌥⌘ Leertaste".
    public var displayLabel: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        switch key {
        case .space: return symbols + " Leertaste"
        case .escape: return symbols + "Esc"
        case .letter(let letter): return symbols + String(letter).uppercased()
        case .digit(let digit): return symbols + String(digit)
        case .function(let number): return symbols + "F\(number)"
        }
    }

    /// macOS virtual key code.
    public var keyCode: UInt32 {
        UInt32(Self.keysByCode.first { $0.value == key }?.key ?? 49)
    }

    /// Carbon modifier mask (cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096).
    public var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= 256 }
        if modifiers.contains(.shift) { mask |= 512 }
        if modifiers.contains(.option) { mask |= 2048 }
        if modifiers.contains(.control) { mask |= 4096 }
        return mask
    }

    private var keyName: String {
        switch key {
        case .space: "space"
        case .escape: "escape"
        case .letter(let letter): String(letter)
        case .digit(let digit): String(digit)
        case .function(let number): "f\(number)"
        }
    }

    private static func key(named name: String) -> Key? {
        switch name {
        case "space": return .space
        case let letter where letter.count == 1 && letter.first?.isLetter == true:
            let key = Key.letter(letter.first ?? "a")
            return keysByCode.values.contains(key) ? key : nil
        case let digit where digit.count == 1 && Int(digit) != nil: return .digit(Int(digit) ?? 0)
        case let function where function.hasPrefix("f"):
            guard let number = Int(function.dropFirst()), (1...12).contains(number) else { return nil }
            return .function(number)
        default: return nil
        }
    }

    private static let keysByCode: [Int: Key] = {
        var keys: [Int: Key] = [49: .space, 53: .escape]
        let letters: [Character: Int] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
            "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
            "k": 40, "n": 45, "m": 46,
        ]
        for (letter, code) in letters { keys[code] = .letter(letter) }
        let digits = [1: 18, 2: 19, 3: 20, 4: 21, 6: 22, 5: 23, 9: 25, 7: 26, 8: 28, 0: 29]
        for (digit, code) in digits { keys[code] = .digit(digit) }
        let functions = [
            1: 122, 2: 120, 3: 99, 4: 118, 5: 96, 6: 97, 7: 98, 8: 100, 9: 101, 10: 109, 11: 103, 12: 111,
        ]
        for (number, code) in functions { keys[code] = .function(number) }
        return keys
    }()
}

/// Tells whether macOS (or another app) already uses a key combination.
public protocol HotkeyConflictChecking: Sendable {
    /// A short description of who uses it, or nil if it is free.
    func conflict(for hotkey: Hotkey) -> String?
}
