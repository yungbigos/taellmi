import Carbon.HIToolbox
import Domain

/// One entry from macOS's shortcut list.
public struct SystemShortcut: Sendable {
    public var keyCode: Int
    public var modifiers: Int
    public var isEnabled: Bool

    public init(keyCode: Int, modifiers: Int, isEnabled: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
    }
}

/// Finds clashes with macOS's own keyboard shortcuts (Spotlight, Finder search, input sources, …),
/// as listed in System Settings → Keyboard → Keyboard Shortcuts.
public struct SystemHotkeyChecker: HotkeyConflictChecking {
    /// Mask of the four modifier keys; system entries can carry extra flag bits.
    private static let modifierMask = cmdKey | shiftKey | optionKey | controlKey
    private let systemShortcuts: @Sendable () -> [SystemShortcut]

    public init(systemShortcuts: @escaping @Sendable () -> [SystemShortcut] = SystemHotkeyChecker.systemShortcuts) {
        self.systemShortcuts = systemShortcuts
    }

    public func conflict(for hotkey: Hotkey) -> String? {
        let clash = systemShortcuts().contains { shortcut in
            shortcut.isEnabled && shortcut.keyCode == Int(hotkey.keyCode)
                && shortcut.modifiers & Self.modifierMask == Int(hotkey.carbonModifiers)
        }
        return clash ? "a macOS shortcut (e.g. Spotlight or Finder search)" : nil
    }

    public static func systemShortcuts() -> [SystemShortcut] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr, let list = array?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return list.compactMap { entry in
            guard let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { return nil }
            return SystemShortcut(
                keyCode: code, modifiers: modifiers,
                isEnabled: entry[kHISymbolicHotKeyEnabled as String] as? Bool ?? false)
        }
    }
}
