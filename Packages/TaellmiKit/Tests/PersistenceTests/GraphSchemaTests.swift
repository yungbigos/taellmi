import GRDB
import Persistence
import TestSupport
import Testing

@Suite("Graph schema")
struct GraphSchemaTests {
    private func insertKinds(_ db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO node_kind (id, name, system) VALUES ('entry', 'Entry', 1), ('person', 'Person', 0);
                INSERT INTO edge_kind (id, name, system, derived) VALUES ('contains', 'contains', 1, 1);
                """)
    }

    @Test("the graph tables exist after migrating")
    func tablesExist() throws {
        let database = try makeDatabase()
        let tables = try database.reader.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        for table in ["node_kind", "edge_kind", "node", "edge"] {
            #expect(tables.contains(table), "missing table \(table)")
        }
    }

    @Test("a system kind cannot be deleted, a configured one can")
    func systemKindsAreProtected() throws {
        let database = try makeDatabase()
        try database.writer.write(insertKinds)
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in try db.execute(sql: "DELETE FROM node_kind WHERE id = 'entry'") }
        }
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in try db.execute(sql: "DELETE FROM edge_kind WHERE id = 'contains'") }
        }
        try database.writer.write { db in try db.execute(sql: "DELETE FROM node_kind WHERE id = 'person'") }
    }

    @Test("a system kind keeps its system flag")
    func systemFlagIsPermanent() throws {
        let database = try makeDatabase()
        try database.writer.write(insertKinds)
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try db.execute(sql: "UPDATE node_kind SET system = 0 WHERE id = 'entry'")
            }
        }
    }

    @Test("a node needs a known kind")
    func nodeKindMustExist() throws {
        let database = try makeDatabase()
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try db.execute(sql: "INSERT INTO node (id, kind, method) VALUES ('n1', 'unknown', 'test')")
            }
        }
    }

    @Test("deleting a node removes its edges")
    func edgesFollowNodes() throws {
        let database = try makeDatabase()
        try database.writer.write { db in
            try insertKinds(db)
            try db.execute(
                sql: """
                    INSERT INTO node (id, kind, method) VALUES ('a', 'entry', 'test'), ('b', 'entry', 'test');
                    INSERT INTO edge (kind, from_id, to_id, method) VALUES ('contains', 'a', 'b', 'test');
                    DELETE FROM node WHERE id = 'b';
                    """)
        }
        let edges = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM edge") }
        #expect(edges == 0)
    }
}
