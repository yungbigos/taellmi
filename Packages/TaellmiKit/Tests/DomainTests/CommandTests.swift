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

@Suite("Formatting commands and their keys")
struct FormattingCommandTests {
    @Test("each format has a command; they are named after the format, as the brand book says")
    func formats() {
        #expect(Command.formatBold.format == .bold)
        #expect(Command.formatNumberedList.format == .numberedList)
        #expect(Command.formatBold.title == "bold")
        #expect(Command.formatStrikethrough.title == "strike through")
        #expect(Command.allCases.filter(\.isFormatting).count == 8)
        #expect(!Command.newThought.isFormatting)
    }

    @Test("⌘] and ⌘[ are valid shortcuts")
    func brackets() throws {
        let indent = try Hotkey(parsing: "command+rightbracket")
        #expect(indent.displayLabel == "⌘]")
        #expect(indent.keyCode == 30)
        #expect(try Hotkey(parsing: "command+leftbracket").displayLabel == "⌘[")
    }

    @Test("a key press matches a shortcut by its letter, or by its key for digits and brackets, on any layout")
    func matching() throws {
        let bold = try Hotkey(parsing: "command+b")
        #expect(bold.matches(keyCode: 11, characters: "b", modifiers: [.command]))
        #expect(!bold.matches(keyCode: 11, characters: "b", modifiers: [.command, .shift]))
        let bullets = try Hotkey(parsing: "command+shift+7")
        #expect(bullets.matches(keyCode: 26, characters: "/", modifiers: [.command, .shift]))
        #expect(bullets.matches(keyCode: 26, characters: "&", modifiers: [.command, .shift]))
        #expect(!bullets.matches(keyCode: 26, characters: "7", modifiers: [.command]))
    }
}
