import Domain
import Testing

@Suite("Commands")
struct CommandTests {
    @Test("every command has a unique id and a title")
    func uniqueIDs() {
        let ids = Commands.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Commands.all.allSatisfy { !$0.title.isEmpty })
    }

    @Test("titles follow the brand book: lowercase, verb + object")
    func lowercaseTitles() {
        #expect(Commands.all.allSatisfy { $0.title == $0.title.lowercased() })
    }

    @Test("each command's shortcut lives in its own setting")
    func settingKeys() {
        #expect(Command.deleteThought.settingKey == "shortcut.thought.delete")
    }

    @Test("⌘⌫ is a valid shortcut")
    func deleteKey() throws {
        let hotkey = try Hotkey(parsing: "command+delete")
        #expect(hotkey.displayLabel == "⌘⌫")
        #expect(hotkey.keyCode == 51)
    }
}
