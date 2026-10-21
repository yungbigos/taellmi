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
        curation: ConceptCuration = ConceptCuration(), now: Date = Date()
    ) throws -> Bool {
        // The model's names go through your renames and merges first; each word keeps the name the model used,
        // so the graph can always be rebuilt from your list (split off, undo).
        let origins = understanding.mentions.map { ConceptName(kind: $0.kind, name: $0.name) }
        var understanding = understanding
        understanding.mentions = understanding.mentions.map { mention in
            let target = curation.resolve(ConceptName(kind: mention.kind, name: mention.name))
            return ConceptMention(kind: target.kind, name: target.name, utf16Range: mention.utf16Range)
        }
        return try database.writer.write { db in
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
            var ranges: [String: (fragment: String, concept: String, ranges: [[Int]], origins: [ConceptName])] = [:]
            for (mention, origin) in zip(understanding.mentions, origins) {
                guard let fragment = fragments.first(where: { $0.range.contains(mention.utf16Range.lowerBound) })
                else { continue }
                let conceptID = Self.conceptID(kind: mention.kind, name: mention.name)
                try db.execute(
                    sql: """
                        INSERT INTO node (id, kind, label, method, created_at) VALUES (?, ?, ?, 'same_name@1', ?)
                        ON CONFLICT(id) DO NOTHING
                        """, arguments: [conceptID, mention.kind, mention.name, now])
                let key = fragment.id + "\u{1}" + conceptID
                ranges[key, default: (fragment.id, conceptID, [], [])].ranges.append(
                    [mention.utf16Range.lowerBound, mention.utf16Range.upperBound])
                ranges[key]?.origins.append(origin)
            }
            for edge in ranges.values {
                let evidence = try Self.encode(Evidence(ranges: edge.ranges, origins: edge.origins))
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

    /// The words a mentions edge marks, and for each the name the model used (older edges: none).
    struct Evidence: Equatable {
        var ranges: [[Int]]
        var origins: [ConceptName]
    }

    static func encode(_ evidence: Evidence) throws -> String {
        let value = JSONValue.object([
            "ranges": .array(evidence.ranges.map { .array($0.map { .number(Double($0)) }) }),
            "origins": .array(
                evidence.origins.map { .object(["kind": .string($0.kind), "name": .string($0.name)]) }),
        ])
        return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    static func decode(_ json: String?, fallback: ConceptName) -> Evidence {
        guard let json, let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else {
            return Evidence(ranges: [], origins: [])
        }
        let ranges = (value.objectValue?["ranges"]?.arrayValue ?? []).map {
            ($0.arrayValue ?? []).compactMap { $0.doubleValue.map(Int.init) }
        }
        let origins = (value.objectValue?["origins"]?.arrayValue ?? []).compactMap { item -> ConceptName? in
            guard let kind = item.objectValue?["kind"]?.stringValue, let name = item.objectValue?["name"]?.stringValue
            else { return nil }
            return ConceptName(kind: kind, name: name)
        }
        // An edge from before origins were kept counts its words as the concept it points to.
        return Evidence(
            ranges: ranges, origins: origins.count == ranges.count ? origins : ranges.map { _ in fallback })
    }

    /// Brings the graph in line with your renames, merges and kind changes. It is rebuilt from what the model
    /// named in each passage, sent through your list, so it follows the list both ways: a merge, a split, an
    /// undo. Your words stay marked; nothing is written when nothing changed.
    public func apply(_ curation: ConceptCuration) throws {
        try database.writer.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id, e.from_id, e.to_id, e.evidence_json, e.model_id, e.prompt_ref, c.kind, c.label
                    FROM edge e JOIN node c ON c.id = e.to_id WHERE e.kind = ?
                    """, arguments: [GraphKinds.mentions])
            struct Wanted {
                var target: ConceptName
                var evidence = Evidence(ranges: [], origins: [])
                var modelID: String?
                var promptRef: String?
            }
            var current: [String: Evidence] = [:]
            var labels: [String: ConceptName] = [:]
            var wanted: [String: Wanted] = [:]
            for row in rows {
                let fragment: String = row["from_id"]
                let concept = ConceptName(kind: row["kind"], name: row["label"])
                let evidence = Self.decode(row["evidence_json"], fallback: concept)
                current[fragment + "\u{1}" + (row["to_id"] as String)] = evidence
                labels[row["to_id"]] = concept
                for (range, origin) in zip(evidence.ranges, evidence.origins) {
                    let target = curation.resolve(origin)
                    let key = fragment + "\u{1}" + Self.conceptID(kind: target.kind, name: target.name)
                    var entry =
                        wanted[key] ?? Wanted(target: target, modelID: row["model_id"], promptRef: row["prompt_ref"])
                    if !zip(entry.evidence.ranges, entry.evidence.origins).contains(where: { $0.0 == range }) {
                        entry.evidence.ranges.append(range)
                        entry.evidence.origins.append(origin)
                    }
                    wanted[key] = entry
                }
            }
            for key in wanted.keys {
                let order = zip(wanted[key]!.evidence.ranges, wanted[key]!.evidence.origins)
                    .sorted { ($0.0.first ?? 0) < ($1.0.first ?? 0) }
                wanted[key]?.evidence = Evidence(ranges: order.map(\.0), origins: order.map(\.1))
            }
            let wantedLabels = Dictionary(
                wanted.values.map { (Self.conceptID(kind: $0.target.kind, name: $0.target.name), $0.target) },
                uniquingKeysWith: { first, _ in first })
            let sameEdges =
                Set(current.keys) == Set(wanted.keys)
                && wanted.allSatisfy { current[$0.key] == $0.value.evidence }
            let sameLabels = wantedLabels.allSatisfy { labels[$0.key]?.name == $0.value.name }
            guard !(sameEdges && sameLabels) else { return }

            let now = Date()
            for (id, target) in wantedLabels {
                try db.execute(
                    sql: """
                        INSERT INTO node (id, kind, label, method, created_at) VALUES (?, ?, ?, 'same_name@1', ?)
                        ON CONFLICT(id) DO UPDATE SET label = excluded.label, kind = excluded.kind
                        """, arguments: [id, target.kind, target.name, now])
            }
            try db.execute(sql: "DELETE FROM edge WHERE kind = ?", arguments: [GraphKinds.mentions])
            for (key, entry) in wanted {
                let fragment = String(key.split(separator: "\u{1}", maxSplits: 1).first ?? "")
                try db.execute(
                    sql: """
                        INSERT INTO edge (kind, from_id, to_id, evidence_json, method, model_id, prompt_ref, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        GraphKinds.mentions, fragment, Self.conceptID(kind: entry.target.kind, name: entry.target.name),
                        try Self.encode(entry.evidence), Self.method, entry.modelID, entry.promptRef, now,
                    ])
            }
            try Self.pruneConcepts(db)
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
                let evidence = Self.decode(
                    row["evidence_json"], fallback: ConceptName(kind: row["kind"], name: row["label"]))
                let found = evidence.ranges.compactMap { $0.count == 2 ? $0[0]..<$0[1] : nil }
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
