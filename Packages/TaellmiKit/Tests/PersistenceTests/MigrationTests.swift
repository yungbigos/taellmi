import GRDB
import Persistence
import TestSupport
import Testing

@Suite("Database migrations")
struct MigrationTests {
    @Test("an empty database migrates to the latest schema")
    func migratesToLatest() throws {
        let database = try makeDatabase()
        let tables = try database.reader.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        for table in [
            "entry", "segment", "job", "provider", "model", "assignment", "prompt", "pipeline_step", "setting",
        ] {
            #expect(tables.contains(table), "missing table \(table)")
        }
    }

    @Test("migrating twice is a no-op")
    func idempotent() throws {
        let queue = try DatabaseQueue()
        _ = try AppDatabase(queue)
        _ = try AppDatabase(queue)
    }

    @Test("origin must be seed or user")
    func originConstraint() throws {
        let database = try makeDatabase()
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try db.execute(
                    sql:
                        "INSERT INTO setting (key, type, value_json, origin, seed_version) VALUES ('x', 'number', '1', 'hacker', 1)"
                )
            }
        }
    }

    @Test("JSON columns reject invalid JSON")
    func jsonConstraint() throws {
        let database = try makeDatabase()
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try db.execute(
                    sql:
                        "INSERT INTO setting (key, type, value_json, origin, seed_version) VALUES ('x', 'number', '{oops', 'seed', 1)"
                )
            }
        }
    }
}
