import Config
import Domain
import TestSupport
import Testing

@testable import AppComposition

@Suite("Command shortcuts from config")
struct CommandShortcutsTests {
    @Test("every command gets its default shortcut from the seeds")
    func defaults() throws {
        let database = try makeDatabase()
        _ = try Seeder(database: database).apply(SeedBundle.bundled())
        let shortcuts = CommandShortcuts.load(from: SettingsStore(database: database))
        #expect(shortcuts[.openPalette] == (try Hotkey(parsing: "command+k")))
        #expect(shortcuts.count == Commands.all.count)
    }

    @Test("a changed shortcut wins; an unreadable one leaves the command without a shortcut")
    func overridesAndInvalid() throws {
        let database = try makeDatabase()
        _ = try Seeder(database: database).apply(SeedBundle.bundled())
        let editor = ConfigEditor(database: database)
        try editor.setSetting(Command.searchThoughts.settingKey, to: .string("control+option+s"))
        try editor.setSetting(Command.showTrash.settingKey, to: .string("nonsense"))
        let shortcuts = CommandShortcuts.load(from: SettingsStore(database: database))
        #expect(shortcuts[.searchThoughts] == (try Hotkey(parsing: "control+option+s")))
        #expect(shortcuts[.showTrash] == nil)
    }
}
