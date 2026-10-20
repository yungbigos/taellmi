import CryptoKit
import Domain
import Foundation
import GRDB

/// A passage of an Entry, as stored in the graph.
public struct StoredFragment: Sendable, Equatable, Identifiable {
    public var id: String
    public var entryID: String
    public var ordinal: Int
    public var text: String
    public var utf16Range: Range<Int>
}

/// Fragments as `fragment` nodes, each contained in its Entry's `entry` node (ADR 0005). All rebuildable.
public struct FragmentStore: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Makes the Entry's Fragments exactly `spans`. A passage whose words did not change keeps its id, and so
    /// its vectors; vectors of passages that are gone are removed. `sourceText` and `method` are what the spans
    /// came from, so a later change to either shows up as stale.
    @discardableResult
    public func replace(entryID: String, spans: [TextSpan], sourceText: String, method: String, now: Date = Date())
        throws -> [StoredFragment]
    {
        var seen: [String: Int] = [:]
        let fragments = spans.enumerated().map { ordinal, span in
            let occurrence = seen[span.text, default: 0]
            seen[span.text] = occurrence + 1
            return StoredFragment(
                id: Self.fragmentID(entryID: entryID, text: span.text, occurrence: occurrence), entryID: entryID,
                ordinal: ordinal, text: span.text, utf16Range: span.utf16Range)
        }
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO node (id, kind, entry_id, text, method, created_at) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET text = excluded.text, method = excluded.method
                    """,
                arguments: [entryID, GraphKinds.entry, entryID, sourceText, method, now])
            let keep = Set(fragments.map(\.id))
            let gone = try String.fetchAll(
                db, sql: "SELECT id FROM node WHERE entry_id = ? AND kind = ?",
                arguments: [entryID, GraphKinds.fragment]
            ).filter { !keep.contains($0) }
            for id in gone { try db.execute(sql: "DELETE FROM node WHERE id = ?", arguments: [id]) }
            try VectorStore.remove(nodeIDs: gone, in: db)
            for fragment in fragments {
                try db.execute(
                    sql: """
                        INSERT INTO node (id, kind, entry_id, ordinal, utf16_start, utf16_end, text, method, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET ordinal = excluded.ordinal,
                            utf16_start = excluded.utf16_start, utf16_end = excluded.utf16_end, method = excluded.method
                        """,
                    arguments: [
                        fragment.id, GraphKinds.fragment, entryID, fragment.ordinal, fragment.utf16Range.lowerBound,
                        fragment.utf16Range.upperBound, fragment.text, method, now,
                    ])
                try db.execute(
                    sql: """
                        INSERT INTO edge (kind, from_id, to_id, method, created_at) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(kind, from_id, to_id) DO NOTHING
                        """,
                    arguments: [GraphKinds.contains, entryID, fragment.id, method, now])
            }
        }
        return fragments
    }

    public func fragments(entryID: String) throws -> [StoredFragment] {
        try database.reader.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM node WHERE entry_id = ? AND kind = ? ORDER BY ordinal",
                arguments: [entryID, GraphKinds.fragment]
            ).map(Self.fragment)
        }
    }

    public func fragments(ids: some Collection<String>) throws -> [StoredFragment] {
        guard !ids.isEmpty else { return [] }
        return try database.reader.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM node WHERE kind = ? AND id IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
                arguments: StatementArguments([GraphKinds.fragment] + Array(ids))
            ).map(Self.fragment)
        }
    }

    /// Entries whose stored passages do not match their current Text: never split, edited since, or split
    /// by another `method`. A blank Entry that was never split (a recording still waiting) is not stale.
    /// One comparison in SQL, so it stays cheap for large Archives.
    public func staleEntryIDs(method: String) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT e.id FROM entry e LEFT JOIN node n ON n.id = e.id AND n.kind = ?
                    WHERE (n.id IS NULL AND trim(e.text, ' ' || char(9, 10, 13)) != '')
                       OR (n.id IS NOT NULL AND (n.text IS NOT e.text OR n.method IS NOT ?))
                    ORDER BY e.created_at
                    """, arguments: [GraphKinds.entry, method])
        }
    }

    /// Entries with at least one passage that has no vector in `space` yet.
    public func entryIDsWithFragmentsMissingVectors(space: String) throws -> Set<String> {
        try database.reader.read { db in
            try String.fetchSet(
                db,
                sql: """
                    SELECT DISTINCT n.entry_id FROM node n
                    WHERE n.kind = ? AND NOT EXISTS (
                        SELECT 1 FROM vector_meta v WHERE v.node_id = n.id AND v.space = ?)
                    """, arguments: [GraphKinds.fragment, space])
        }
    }

    private static func fragment(_ row: Row) -> StoredFragment {
        StoredFragment(
            id: row["id"], entryID: row["entry_id"], ordinal: row["ordinal"], text: row["text"],
            utf16Range: (row["utf16_start"] as Int)..<(row["utf16_end"] as Int))
    }

    /// Content-derived, so the same words in the same Entry get the same id after a rebuild or an edit elsewhere.
    static func fragmentID(entryID: String, text: String, occurrence: Int) -> String {
        let digest = SHA256.hash(data: Data("\(entryID)\n\(occurrence)\n\(text)".utf8))
        return "fragment-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
