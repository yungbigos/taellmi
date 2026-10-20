import Domain
import Foundation
import GRDB

/// The summary and Concepts of one thought, and the Text they were made from: Concept positions only fit
/// that Text.
public struct ThoughtUnderstanding: Sendable, Equatable {
    public var summary: String?
    public var concepts: [ThoughtConcept]
    public var sourceText: String?
}

/// Which model and prompts produced an Understanding (ADR 0005: every derived row records how it was made).
public struct UnderstandingProvenance: Sendable, Equatable {
    public var modelID: String
    /// The prompts used, as `id@version` joined by `+`. A change makes every thought stale.
    public var promptRefs: String

    public init(modelID: String, promptRefs: String) {
        self.modelID = modelID
        self.promptRefs = promptRefs
    }
}

/// Summaries and Concepts in the graph (ADR 0012).
/// - A summary node per Entry (kind `summary`), holding the Text and prompts it was made from, so stale ones
///   are one SQL comparison. It exists even when there is no summary (a short thought), to mark "done".
/// - Concept nodes across Entries, identified by kind and lower-cased name: the same name is the same Concept.
/// - `mentions` edges from the passage that contains the words to the Concept, with the exact ranges.
public struct UnderstandingStore: Sendable {
    static let method = "understand@1"
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public static func conceptID(kind: String, name: String) -> String {
        "concept:\(kind):\(name.lowercased())"
    }

    /// Stores what a model made of a thought. Returns false and stores nothing when the Text, or how it is
    /// split into passages, changed while the model was working: the positions wouldn't fit. The thought is
    /// then stale and understood again.
    @discardableResult
    public func replace(
        entryID: String, sourceText: String, understanding: Understanding, provenance: UnderstandingProvenance,
        now: Date = Date()
    ) throws -> Bool {
        try database.writer.write { db in
            guard
                try String.fetchOne(db, sql: "SELECT text FROM entry WHERE id = ?", arguments: [entryID]) == sourceText
            else { return false }
            let split = try Row.fetchOne(
                db, sql: "SELECT text, method FROM node WHERE id = ? AND kind = ?",
                arguments: [entryID, GraphKinds.entry])
            let splitMethod: String? = split?["method"]
            if !understanding.mentions.isEmpty, (split?["text"] as String?) != sourceText { return false }
            var payloadFields: [String: JSONValue] = [
                "source": .string(sourceText), "prompts": .string(provenance.promptRefs),
            ]
            if let splitMethod { payloadFields["split"] = .string(splitMethod) }
            let payload = String(decoding: try JSONEncoder().encode(JSONValue.object(payloadFields)), as: UTF8.self)
            let fragments = try Row.fetchAll(
                db, sql: "SELECT id, utf16_start, utf16_end FROM node WHERE entry_id = ? AND kind = ?",
                arguments: [entryID, GraphKinds.fragment]
            ).map { (id: $0["id"] as String, range: ($0["utf16_start"] as Int)..<($0["utf16_end"] as Int)) }
            try db.execute(
                sql: """
                    DELETE FROM edge WHERE kind = ? AND method = ?
                    AND from_id IN (SELECT id FROM node WHERE entry_id = ? AND kind = ?)
                    """, arguments: [GraphKinds.mentions, Self.method, entryID, GraphKinds.fragment])
            try db.execute(
                sql: """
                    INSERT INTO node (id, kind, entry_id, text, payload_json, method, model_id, prompt_ref, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET text = excluded.text, payload_json = excluded.payload_json,
                        method = excluded.method, model_id = excluded.model_id, prompt_ref = excluded.prompt_ref,
                        created_at = excluded.created_at
                    """,
                arguments: [
                    "summary:\(entryID)", GraphKinds.summary, entryID, understanding.summary, payload, Self.method,
                    provenance.modelID, provenance.promptRefs, now,
                ])
            // Ranges per (passage, Concept); a mention outside every passage (not split yet) is skipped.
            var ranges: [String: (fragment: String, concept: String, ranges: [[Int]])] = [:]
            for mention in understanding.mentions {
                guard let fragment = fragments.first(where: { $0.range.contains(mention.utf16Range.lowerBound) })
                else { continue }
                let conceptID = Self.conceptID(kind: mention.kind, name: mention.name)
                try db.execute(
                    sql: """
                        INSERT INTO node (id, kind, label, method, created_at) VALUES (?, ?, ?, 'same_name@1', ?)
                        ON CONFLICT(id) DO NOTHING
                        """, arguments: [conceptID, mention.kind, mention.name, now])
                let key = fragment.id + "\u{1}" + conceptID
                ranges[key, default: (fragment.id, conceptID, [])].ranges.append(
                    [mention.utf16Range.lowerBound, mention.utf16Range.upperBound])
            }
            for edge in ranges.values {
                let evidence = String(
                    decoding: try JSONEncoder().encode(["ranges": edge.ranges]), as: UTF8.self)
                try db.execute(
                    sql: """
                        INSERT INTO edge (kind, from_id, to_id, evidence_json, method, model_id, prompt_ref, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(kind, from_id, to_id) DO UPDATE SET evidence_json = excluded.evidence_json
                        """,
                    arguments: [
                        GraphKinds.mentions, edge.fragment, edge.concept, evidence, Self.method, provenance.modelID,
                        provenance.promptRefs, now,
                    ])
            }
            try Self.pruneConcepts(db)
            return true
        }
    }

    /// Fires after summaries or concepts were stored.
    public func changes() -> AsyncStream<Void> {
        let writer = database.writer
        return AsyncStream { continuation in
            let observation = DatabaseRegionObservation(tracking: Table("node"), Table("edge"))
            let cancellable = observation.start(in: writer) { _ in
                continuation.finish()
            } onChange: { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Removes Concepts no passage mentions any more (e.g. after a thought was deleted). Returns how many.
    @discardableResult
    public func pruneConcepts() throws -> Int {
        try database.writer.write { db in try Self.pruneConcepts(db) }
    }

    @discardableResult
    static func pruneConcepts(_ db: Database) throws -> Int {
        try db.execute(
            sql: """
                DELETE FROM node WHERE entry_id IS NULL AND method = 'same_name@1'
                AND id NOT IN (SELECT to_id FROM edge WHERE kind = ?)
                """, arguments: [GraphKinds.mentions])
        return db.changesCount
    }

    public func understanding(entryID: String) throws -> ThoughtUnderstanding? {
        try database.reader.read { db in
            guard
                let summary = try Row.fetchOne(
                    db, sql: "SELECT text, json_extract(payload_json, '$.source') AS source FROM node WHERE id = ?",
                    arguments: ["summary:\(entryID)"])
            else { return nil }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT c.id, c.kind, c.label, e.evidence_json FROM edge e
                    JOIN node f ON f.id = e.from_id JOIN node c ON c.id = e.to_id
                    WHERE e.kind = ? AND f.entry_id = ? ORDER BY f.ordinal, e.id
                    """, arguments: [GraphKinds.mentions, entryID])
            var concepts: [ThoughtConcept] = []
            for row in rows {
                let evidence = try JSONDecoder().decode(
                    [String: [[Int]]].self, from: Data((row["evidence_json"] as String).utf8))
                let found = (evidence["ranges"] ?? []).compactMap { $0.count == 2 ? $0[0]..<$0[1] : nil }
                if let index = concepts.firstIndex(where: { $0.id == row["id"] as String }) {
                    concepts[index].utf16Ranges += found
                } else {
                    concepts.append(
                        ThoughtConcept(id: row["id"], kind: row["kind"], name: row["label"], utf16Ranges: found))
                }
            }
            for index in concepts.indices { concepts[index].utf16Ranges.sort { $0.lowerBound < $1.lowerBound } }
            concepts.sort { ($0.utf16Ranges.first?.lowerBound ?? 0) < ($1.utf16Ranges.first?.lowerBound ?? 0) }
            return ThoughtUnderstanding(summary: summary["text"], concepts: concepts, sourceText: summary["source"])
        }
    }

    /// Every Concept with at least one mention, most-mentioned first.
    public func concepts() throws -> [ConceptSummary] {
        try database.reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT c.id, c.kind, c.label, COUNT(DISTINCT f.entry_id) AS thoughts FROM node c
                    JOIN edge e ON e.to_id = c.id AND e.kind = ? JOIN node f ON f.id = e.from_id
                    GROUP BY c.id ORDER BY thoughts DESC, c.label COLLATE NOCASE
                    """, arguments: [GraphKinds.mentions]
            ).map { ConceptSummary(id: $0["id"], kind: $0["kind"], name: $0["label"], thoughtCount: $0["thoughts"]) }
        }
    }

    /// Thoughts that mention a Concept, newest first.
    public func entryIDs(mentioning conceptID: String) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT f.entry_id FROM edge e JOIN node f ON f.id = e.from_id JOIN entry t ON t.id = f.entry_id
                    WHERE e.kind = ? AND e.to_id = ? GROUP BY f.entry_id ORDER BY MAX(t.created_at) DESC
                    """, arguments: [GraphKinds.mentions, conceptID])
        }
    }

    /// Concepts mentioned in the same thoughts, most shared thoughts first.
    public func appearingWith(_ conceptID: String) throws -> [ConceptSummary] {
        try database.reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    WITH mine AS (
                        SELECT DISTINCT f.entry_id FROM edge e JOIN node f ON f.id = e.from_id
                        WHERE e.kind = ? AND e.to_id = ?)
                    SELECT c.id, c.kind, c.label, COUNT(DISTINCT f.entry_id) AS thoughts FROM edge e
                    JOIN node f ON f.id = e.from_id JOIN node c ON c.id = e.to_id
                    WHERE e.kind = ? AND f.entry_id IN (SELECT entry_id FROM mine) AND c.id != ?
                    GROUP BY c.id ORDER BY thoughts DESC, c.label COLLATE NOCASE
                    """, arguments: [GraphKinds.mentions, conceptID, GraphKinds.mentions, conceptID]
            ).map { ConceptSummary(id: $0["id"], kind: $0["kind"], name: $0["label"], thoughtCount: $0["thoughts"]) }
        }
    }

    /// The enabled kinds of Concept with their words and symbols from config, in their configured order.
    public func conceptKindDetails() throws -> [ConceptKind] {
        try database.reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, name, style_json FROM node_kind WHERE parent_id = ? AND enabled
                    ORDER BY COALESCE(json_extract(style_json, '$.order'), 999), id
                    """, arguments: [GraphKinds.concept]
            ).map { row in
                let style = (row["style_json"] as String?).flatMap {
                    try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8))
                }
                return ConceptKind(
                    id: row["id"], plural: style?["plural"]?.stringValue ?? (row["name"] as String).lowercased(),
                    symbol: style?["symbol"]?.stringValue ?? "circle")
            }
        }
    }

    /// The enabled kinds of Concept (children of `concept` in config).
    public func conceptKinds() throws -> Set<String> {
        try database.reader.read { db in
            Set(
                try String.fetchAll(
                    db, sql: "SELECT id FROM node_kind WHERE parent_id = ? AND enabled", arguments: [GraphKinds.concept]
                ))
        }
    }

    /// Thoughts whose understanding is missing, or was made from other Text, other prompts or other passages.
    /// Only thoughts already split into passages for their current Text: the others wait for that first.
    public func staleEntryIDs(promptRefs: String) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT e.id FROM entry e
                    JOIN node n ON n.id = e.id AND n.kind = ? AND n.text IS e.text
                    LEFT JOIN node s ON s.id = 'summary:' || e.id
                    WHERE s.id IS NULL OR json_extract(s.payload_json, '$.source') IS NOT e.text
                       OR s.prompt_ref IS NOT ? OR json_extract(s.payload_json, '$.split') IS NOT n.method
                    ORDER BY e.created_at DESC
                    """, arguments: [GraphKinds.entry, promptRefs])
        }
    }
}
