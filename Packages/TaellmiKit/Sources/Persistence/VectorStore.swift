import Foundation
import GRDB

/// Embedding vectors in sqlite-vec tables, one table per vector size (`vec_d<size>`), partitioned by vector
/// space: the model and settings that made them (`ModelConfig.vectorSpace`). `vector_meta` records which node
/// has a vector in which space, so checking what is missing never scans the vectors.
///
/// A node keeps one vector per size: re-embedding in another space of the same size replaces it, which is
/// what a model swap wants. Vectors are derived data and can always be recomputed.
public struct VectorStore: Sendable {
    public struct Hit: Sendable, Equatable {
        public var nodeID: String
        /// Cosine similarity, 1 for the same direction.
        public var similarity: Double
    }

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func upsert(_ vectors: [(nodeID: String, vector: [Float])], space: String) throws {
        guard !vectors.isEmpty else { return }
        try database.writer.write { db in
            for (nodeID, vector) in vectors {
                let table = try Self.ensureTable(dimensions: vector.count, in: db)
                try db.execute(sql: "DELETE FROM \(table) WHERE node_id = ?", arguments: [nodeID])
                try db.execute(
                    sql: "DELETE FROM vector_meta WHERE node_id = ? AND dimensions = ?",
                    arguments: [nodeID, vector.count])
                try db.execute(
                    sql: "INSERT INTO \(table) (node_id, model_id, embedding) VALUES (?, ?, ?)",
                    arguments: [nodeID, space, Self.blob(vector)])
                try db.execute(
                    sql: "INSERT INTO vector_meta (node_id, space, dimensions) VALUES (?, ?, ?)",
                    arguments: [nodeID, space, vector.count])
            }
        }
    }

    /// The `limit` nodes closest to `vector` within `space`, closest first.
    public func nearest(to vector: [Float], space: String, limit: Int) throws -> [Hit] {
        let table = Self.tableName(dimensions: vector.count)
        return try database.reader.read { db in
            guard try db.tableExists(table) else { return [] }
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT node_id, distance FROM \(table)
                    WHERE embedding MATCH ? AND model_id = ? AND k = ? ORDER BY distance
                    """,
                arguments: [Self.blob(vector), space, limit]
            ).map { Hit(nodeID: $0["node_id"], similarity: 1 - ($0["distance"] as Double)) }
        }
    }

    /// Every node that has a vector in `space`.
    public func nodeIDs(space: String) throws -> Set<String> {
        try database.reader.read { db in
            try String.fetchSet(db, sql: "SELECT node_id FROM vector_meta WHERE space = ?", arguments: [space])
        }
    }

    /// Those of `candidates` that have a vector in `space`.
    public func nodeIDs(space: String, among candidates: some Collection<String>) throws -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        return try database.reader.read { db in
            try String.fetchSet(
                db,
                sql: """
                    SELECT node_id FROM vector_meta
                    WHERE space = ? AND node_id IN (\(candidates.map { _ in "?" }.joined(separator: ",")))
                    """,
                arguments: StatementArguments([space] + Array(candidates)))
        }
    }

    public func remove(nodeIDs: some Collection<String>) throws {
        guard !nodeIDs.isEmpty else { return }
        try database.writer.write { db in try Self.remove(nodeIDs: nodeIDs, in: db) }
    }

    /// Deletes vectors whose node no longer exists (e.g. after its Entry was deleted).
    public func pruneOrphans() throws {
        let orphans = try database.reader.read { db in
            try String.fetchAll(
                db, sql: "SELECT DISTINCT node_id FROM vector_meta WHERE node_id NOT IN (SELECT id FROM node)")
        }
        try remove(nodeIDs: orphans)
    }

    static func remove(nodeIDs: some Collection<String>, in db: Database) throws {
        for id in nodeIDs {
            let sizes = try Int.fetchAll(
                db, sql: "SELECT DISTINCT dimensions FROM vector_meta WHERE node_id = ?", arguments: [id])
            for size in sizes where try db.tableExists(tableName(dimensions: size)) {
                try db.execute(sql: "DELETE FROM \(tableName(dimensions: size)) WHERE node_id = ?", arguments: [id])
            }
            try db.execute(sql: "DELETE FROM vector_meta WHERE node_id = ?", arguments: [id])
        }
    }

    private static func tableName(dimensions: Int) -> String { "vec_d\(dimensions)" }

    /// The vector tables are created on demand because their size is part of the table definition and depends
    /// on the configured model. They are a rebuildable cache, not part of the migrated schema.
    private static func ensureTable(dimensions: Int, in db: Database) throws -> String {
        let table = tableName(dimensions: dimensions)
        try db.execute(
            sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS \(table) USING vec0(
                    node_id TEXT PRIMARY KEY, model_id TEXT PARTITION KEY,
                    embedding float[\(dimensions)] distance_metric=cosine)
                """)
        return table
    }

    private static func blob(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
