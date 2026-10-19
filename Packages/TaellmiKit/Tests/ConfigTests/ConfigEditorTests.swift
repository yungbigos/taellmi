import Config
import Domain
import GRDB
import Persistence
import TestSupport
import Testing

@Suite("Editing config on the user's behalf")
struct ConfigEditorTests {
    private func seeded() throws -> AppDatabase {
        let database = try makeDatabase()
        _ = try Seeder(database: database).apply(SeedBundle.bundled())
        return database
    }

    @Test("changing a setting stores the value and marks it as the user's")
    func setSetting() throws {
        let database = try seeded()
        try ConfigEditor(database: database).setSetting(SettingKeys.idleUnloadSeconds, to: .number(15))
        #expect(try SettingsStore(database: database).number(SettingKeys.idleUnloadSeconds) == 15)
        let origin = try database.reader.read { db in
            try String.fetchOne(
                db, sql: "SELECT origin FROM setting WHERE key = ?", arguments: [SettingKeys.idleUnloadSeconds])
        }
        #expect(origin == "user")
    }

    @Test("changing an unknown setting is an error, not a silent no-op")
    func unknownSetting() throws {
        #expect(throws: SettingsError.missing("does.not.exist")) {
            try ConfigEditor(database: try seeded()).setSetting("does.not.exist", to: .bool(true))
        }
    }

    @Test("assigning a model adds a user assignment and keeps the previous one as fallback")
    func assign() throws {
        let database = try seeded()
        try ConfigEditor(database: database).assign(.transcription, modelID: "parakeet-tdt-0.6b-v3", priority: 0)
        let rows = try database.reader.read { db in
            try Row.fetchAll(
                db, sql: "SELECT origin, priority FROM assignment WHERE role = 'transcription' ORDER BY priority")
        }
        #expect(rows.map { $0["origin"] as String } == ["user", "seed"])
    }
}
