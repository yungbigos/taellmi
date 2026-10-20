import GRDB
import Persistence
import TestSupport
import Testing

@Suite("Vector store")
struct VectorStoreTests {
    @Test("nearest returns the closest vectors first, with their similarity")
    func nearestFirst() throws {
        let store = VectorStore(database: try makeDatabase())
        try store.upsert([("north", [0, 1, 0]), ("east", [1, 0, 0]), ("north-east", [0.7, 0.7, 0])], space: "m")
        let hits = try store.nearest(to: [0.1, 1, 0], space: "m", limit: 2)
        #expect(hits.map(\.nodeID) == ["north", "north-east"])
        #expect(try #require(hits.first).similarity > 0.99)
    }

    @Test("only vectors from the asked model are compared")
    func separatesModels() throws {
        let store = VectorStore(database: try makeDatabase())
        try store.upsert([("old", [0, 1, 0])], space: "old-model")
        try store.upsert([("new", [1, 0, 0])], space: "new-model")
        #expect(try store.nearest(to: [0, 1, 0], space: "new-model", limit: 5).map(\.nodeID) == ["new"])
    }

    @Test("storing a vector for the same node and model replaces it")
    func replaces() throws {
        let store = VectorStore(database: try makeDatabase())
        try store.upsert([("a", [1, 0, 0])], space: "m")
        try store.upsert([("a", [0, 0, 1])], space: "m")
        let hits = try store.nearest(to: [0, 0, 1], space: "m", limit: 5)
        #expect(hits.map(\.nodeID) == ["a"])
        #expect(try #require(hits.first).similarity > 0.99)
    }

    @Test("vectors of different sizes are kept apart")
    func differentDimensions() throws {
        let store = VectorStore(database: try makeDatabase())
        try store.upsert([("small", [1, 0, 0])], space: "small-model")
        try store.upsert([("large", [1, 0, 0, 0])], space: "large-model")
        #expect(try store.nearest(to: [1, 0, 0, 0], space: "large-model", limit: 5).map(\.nodeID) == ["large"])
        #expect(try store.nodeIDs(space: "small-model") == ["small"])
        #expect(try store.nearest(to: [1, 0, 0], space: "small-model", limit: 5).map(\.nodeID) == ["small"])
    }

    @Test("removing nodes removes their vectors from every model")
    func removes() throws {
        let store = VectorStore(database: try makeDatabase())
        try store.upsert([("a", [1, 0, 0]), ("b", [0, 1, 0])], space: "m")
        try store.upsert([("a", [1, 0, 0, 0])], space: "other")
        try store.remove(nodeIDs: ["a"])
        #expect(try store.nodeIDs(space: "m") == ["b"])
        #expect(try store.nodeIDs(space: "other") == [])
    }

    @Test("vectors whose node is gone are pruned")
    func prunesOrphans() throws {
        let database = try makeDatabase()
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO node_kind (id, name, system) VALUES ('fragment', 'Fragment', 1);
                    INSERT INTO node (id, kind, method) VALUES ('kept', 'fragment', 'test');
                    """)
        }
        let store = VectorStore(database: database)
        try store.upsert([("kept", [1, 0, 0]), ("gone", [0, 1, 0])], space: "m")
        try store.pruneOrphans()
        #expect(try store.nodeIDs(space: "m") == ["kept"])
    }

    @Test("an empty store finds nothing instead of failing")
    func emptyStore() throws {
        let store = VectorStore(database: try makeDatabase())
        #expect(try store.nearest(to: [1, 0, 0], space: "m", limit: 5).isEmpty)
        #expect(try store.nodeIDs(space: "m").isEmpty)
    }

    @Test("a vector from another space of the same size replaces the old one, which then no longer counts")
    func sameSizeOtherSpace() throws {
        let store = VectorStore(database: try makeDatabase())
        try store.upsert([("a", [1, 0, 0])], space: "old")
        try store.upsert([("a", [0, 1, 0])], space: "new")
        #expect(try store.nodeIDs(space: "old").isEmpty)
        #expect(try store.nodeIDs(space: "new") == ["a"])
    }

    @Test("only the asked nodes are checked for a vector")
    func checksAmongNodes() throws {
        let store = VectorStore(database: try makeDatabase())
        try store.upsert([("a", [1, 0, 0]), ("b", [0, 1, 0])], space: "m")
        #expect(try store.nodeIDs(space: "m", among: ["a", "c"]) == ["a"])
    }

    @Test("a file database registers vector search on every connection, readers included")
    func fileDatabaseReaders() throws {
        let folder = try TemporaryDirectory()
        let database = try AppDatabase.open(at: folder.url.appendingPathComponent("test.sqlite"))
        let store = VectorStore(database: database)
        try store.upsert([("a", [1, 0, 0])], space: "m")
        #expect(try store.nearest(to: [1, 0, 0], space: "m", limit: 1).map(\.nodeID) == ["a"])
        let version = try database.reader.read { db in try String.fetchOne(db, sql: "SELECT vec_version()") }
        #expect(version?.hasPrefix("v0.1") == true)
    }
}
