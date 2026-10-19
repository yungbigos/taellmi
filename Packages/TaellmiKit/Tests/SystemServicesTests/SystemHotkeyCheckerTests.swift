import Carbon.HIToolbox
import Domain
import SystemServices
import Testing

@Suite("Finding macOS shortcuts that clash with tälli's hotkey")
struct SystemHotkeyCheckerTests {
    private func entry(code: Int, modifiers: Int, enabled: Bool) -> SystemShortcut {
        SystemShortcut(keyCode: code, modifiers: modifiers, isEnabled: enabled)
    }

    @Test("an enabled system shortcut with the same keys is a clash; a disabled one is not")
    func detects() throws {
        let optionCommandSpace = try Hotkey(parsing: "option+command+space")
        let enabled = [entry(code: kVK_Space, modifiers: cmdKey | optionKey, enabled: true)]
        let disabled = [entry(code: kVK_Space, modifiers: cmdKey | optionKey, enabled: false)]
        #expect(SystemHotkeyChecker(systemShortcuts: { enabled }).conflict(for: optionCommandSpace) != nil)
        #expect(SystemHotkeyChecker(systemShortcuts: { disabled }).conflict(for: optionCommandSpace) == nil)
    }

    @Test("extra flag bits in the system entry (e.g. function key) do not hide a clash")
    func ignoresExtraBits() throws {
        let entries = [entry(code: kVK_Space, modifiers: cmdKey | controlKey | 0x100000, enabled: true)]
        #expect(
            SystemHotkeyChecker(systemShortcuts: { entries }).conflict(
                for: try Hotkey(parsing: "control+command+space"))
                != nil)
    }
}
