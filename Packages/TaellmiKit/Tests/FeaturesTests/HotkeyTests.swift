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
