import Domain
import Features
import Testing

@Suite("Global hotkey from config")
struct HotkeyTests {
    @Test(
        "parses a hotkey description",
        arguments: [
            ("option+command+space", Hotkey(key: .space, modifiers: [.option, .command])),
            ("control+shift+r", Hotkey(key: .letter("r"), modifiers: [.control, .shift])),
            ("Command+Option+T", Hotkey(key: .letter("t"), modifiers: [.command, .option])),
        ])
    func parses(text: String, expected: Hotkey) throws {
        #expect(try Hotkey(parsing: text) == expected)
    }

    @Test(
        "rejects hotkeys without a modifier or with unknown parts", arguments: ["space", "hyper+space", "option+", ""])
    func rejects(text: String) {
        #expect(throws: Hotkey.ParseError.self) { try Hotkey(parsing: text) }
    }
}

@Suite("Recording and saving a hotkey")
struct HotkeyRoundTripTests {
    @Test(
        "every hotkey writes back to the same setting text",
        arguments: [
            "option+command+space", "control+shift+r", "control+option+command+t", "option+f5", "command+shift+7",
        ])
    func roundTrip(text: String) throws {
        #expect(try Hotkey(parsing: text).settingValue == text)
    }

    @Test("a key press with modifiers becomes a hotkey; without modifiers it is rejected")
    func fromKeyPress() {
        #expect(
            Hotkey(keyCode: 17, command: true, option: false, control: true, shift: false)
                == Hotkey(key: .letter("t"), modifiers: [.command, .control]))
        #expect(Hotkey(keyCode: 17, command: false, option: false, control: false, shift: true) == nil)
        #expect(Hotkey(keyCode: 999, command: true, option: false, control: false, shift: false) == nil)
    }

    @Test("shows a readable label")
    func label() throws {
        #expect(try Hotkey(parsing: "control+option+command+t").displayLabel == "⌃⌥⌘T")
        #expect(try Hotkey(parsing: "option+command+space").displayLabel == "⌥⌘ Leertaste")
    }
}

@Suite("Keys that only work while tälli is open")
struct SingleKeyTests {
    @Test(
        "Enter and Esc can be set without modifiers",
        arguments: [("return", Hotkey.Key.enter, "↩"), ("escape", .escape, "Esc")])
    func parses(text: String, key: Hotkey.Key, label: String) throws {
        let hotkey = try Hotkey(parsingKey: text)
        #expect(hotkey == Hotkey(key: key, modifiers: []))
        #expect(hotkey.displayLabel == label)
        #expect(hotkey.settingValue == text)
    }

    @Test("Enter is macOS key code 36")
    func enterKeyCode() {
        #expect(Hotkey.enter.keyCode == 36)
    }

    @Test("unknown single keys are rejected")
    func rejects() {
        #expect(throws: Hotkey.ParseError.self) { try Hotkey(parsingKey: "hyper") }
    }
}
