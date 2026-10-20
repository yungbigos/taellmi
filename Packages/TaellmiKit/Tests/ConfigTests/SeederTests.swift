import Config
import Domain
import GRDB
import Persistence
import TestSupport
import Testing

@Suite("Seeding defaults into the database")
struct SeederTests {
    @Test("first launch inserts every seed row")
    func insertsEverything() throws {
        let database = try makeDatabase()
        let bundle = try SeedBundle.bundled()
        let report = try Seeder(database: database).apply(bundle)
        #expect(report.inserted == bundle.rowCount)
        #expect(report.updated == 0)
    }

    @Test("seeding twice is a no-op")
    func idempotent() throws {
        let database = try makeDatabase()
        let bundle = try SeedBundle.bundled()
        _ = try Seeder(database: database).apply(bundle)
        let second = try Seeder(database: database).apply(bundle)
        #expect(second.inserted == 0)
        #expect(second.updated == 0)
    }

    @Test("a newer seed version updates rows that are still defaults")
    func upgradesSeedRows() throws {
        let database = try makeDatabase()
        var bundle = try SeedBundle.bundled()
        _ = try Seeder(database: database).apply(bundle)

        bundle.settings = bundle.settings.map { setting in
            guard setting.key == SettingKeys.idleUnloadSeconds else { return setting }
            var changed = setting
            changed.value = .number(120)
            changed.seedVersion += 1
            return changed
        }
        let report = try Seeder(database: database).apply(bundle)

        #expect(report.updated == 1)
        #expect(try SettingsStore(database: database).number(SettingKeys.idleUnloadSeconds) == 120)
    }

    @Test("user-edited rows survive a seed upgrade")
    func userEditsSurvive() throws {
        let database = try makeDatabase()
        var bundle = try SeedBundle.bundled()
        _ = try Seeder(database: database).apply(bundle)
        try ConfigEditor(database: database).setSetting(SettingKeys.idleUnloadSeconds, to: .number(15))

        bundle.settings = bundle.settings.map { setting in
            var changed = setting
            changed.seedVersion += 1
            changed.value = setting.key == SettingKeys.idleUnloadSeconds ? .number(999) : setting.value
            return changed
        }
        let report = try Seeder(database: database).apply(bundle)

        #expect(report.skippedUserEdited == 1)
        #expect(try SettingsStore(database: database).number(SettingKeys.idleUnloadSeconds) == 15)
    }

    @Test("new rows in a later seed are added without touching existing ones")
    func addsNewRows() throws {
        let database = try makeDatabase()
        var bundle = try SeedBundle.bundled()
        _ = try Seeder(database: database).apply(bundle)
        bundle.settings.append(SeedBundle.Setting(key: "test.new", type: "bool", value: .bool(true), seedVersion: 1))
        let report = try Seeder(database: database).apply(bundle)
        #expect(report.inserted == 1)
    }

    @Test("seeding fills the graph kind tables")
    func seedsGraphKinds() throws {
        let database = try makeDatabase()
        _ = try Seeder(database: database).apply(SeedBundle.bundled())
        let system = try database.reader.read { db in
            try String.fetchSet(db, sql: "SELECT id FROM node_kind WHERE system")
        }
        #expect(system.isSuperset(of: GraphKinds.systemNodeKinds))
    }

    @Test("a kind under a kind under concept is seeded even when listed before its parent")
    func seedsNestedKinds() throws {
        let database = try makeDatabase()
        var bundle = try SeedBundle.bundled()
        var mother = try #require(bundle.nodeKinds.first { $0.id == "person" })
        mother.id = "family"
        mother.parentID = "person"
        bundle.nodeKinds.insert(mother, at: 0)
        _ = try Seeder(database: database).apply(bundle)
        let parent = try database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT parent_id FROM node_kind WHERE id = 'family'")
        }
        #expect(parent == "person")
    }
}
