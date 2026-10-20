import Domain
import Foundation
import GRDB
import Persistence

/// Writes the default config into the database without ever overwriting the user's own edits.
///
/// - Missing rows are inserted (`origin = 'seed'`).
/// - Rows still at their default are updated when the seed's `seed_version` is newer.
/// - Rows with `origin = 'user'` are never touched.
public struct Seeder: Sendable {
    public struct Report: Sendable, Equatable {
        public var inserted = 0
        public var updated = 0
        public var skippedUserEdited = 0
    }

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func apply(_ bundle: SeedBundle) throws -> Report {
        try database.writer.write { db in
            var report = Report()
            for row in Self.rows(from: bundle) { try Self.apply(row, in: db, report: &report) }
            return report
        }
    }

    // MARK: - Generic row handling

    private struct Row {
        var table: String
        var key: [String: any DatabaseValueConvertible]
        var values: [String: (any DatabaseValueConvertible)?]
        var seedVersion: Int
    }

    private static func apply(_ row: Row, in db: Database, report: inout Report) throws {
        let keyColumns = row.key.keys.sorted()
        let whereClause = keyColumns.map { "\($0) = ?" }.joined(separator: " AND ")
        let keyArguments = StatementArguments(keyColumns.map { row.key[$0] })
        let existing = try GRDB.Row.fetchOne(
            db, sql: "SELECT origin, seed_version FROM \(row.table) WHERE \(whereClause)", arguments: keyArguments)

        var columns = row.values
        columns["seed_version"] = row.seedVersion
        if let existing {
            let origin: String = existing["origin"]
            let version: Int = existing["seed_version"]
            if origin == "user" {
                report.skippedUserEdited += 1
                return
            }
            guard row.seedVersion > version else { return }
            let names = columns.keys.sorted()
            try db.execute(
                sql:
                    "UPDATE \(row.table) SET \(names.map { "\($0) = ?" }.joined(separator: ", ")) WHERE \(whereClause)",
                arguments: StatementArguments(names.map { columns[$0] ?? nil }) + keyArguments)
            report.updated += 1
        } else {
            for (name, value) in row.key { columns[name] = value }
            columns["origin"] = "seed"
            let names = columns.keys.sorted()
            try db.execute(
                sql: """
                    INSERT INTO \(row.table) (\(names.joined(separator: ", ")))
                    VALUES (\(Array(repeating: "?", count: names.count).joined(separator: ", ")))
                    """,
                arguments: StatementArguments(names.map { columns[$0] ?? nil }))
            report.inserted += 1
        }
    }

    private static func rows(from bundle: SeedBundle) -> [Row] {
        var rows: [Row] = []
        for p in bundle.providers {
            rows.append(
                Row(
                    table: "provider", key: ["id": p.id],
                    values: ["kind": p.kind, "name": p.name, "base_url": p.baseURL, "enabled": p.enabled],
                    seedVersion: p.seedVersion))
        }
        for m in bundle.models {
            rows.append(
                Row(
                    table: "model", key: ["id": m.id],
                    values: [
                        "name": m.name, "engine": m.engine, "provider_id": m.providerID, "source_ref": m.sourceRef,
                        "revision": m.revision, "files_json": json(m.files), "params_json": json(m.params),
                        "capabilities_json": json(m.capabilities), "est_memory_mb": m.estimatedMemoryMB,
                        "license": m.license, "enabled": m.enabled,
                    ],
                    seedVersion: m.seedVersion))
        }
        for a in bundle.assignments {
            rows.append(
                Row(
                    table: "assignment", key: ["id": a.id],
                    values: [
                        "role": a.role, "priority": a.priority, "model_id": a.modelID,
                        "conditions_json": json(a.conditions), "enabled": a.enabled,
                    ],
                    seedVersion: a.seedVersion))
        }
        for s in bundle.pipeline {
            rows.append(
                Row(
                    table: "pipeline_step", key: ["id": s.id],
                    values: [
                        "step": s.step, "ordinal": s.ordinal, "role": s.role, "conditions_json": json(s.conditions),
                        "enabled": s.enabled,
                    ],
                    seedVersion: s.seedVersion))
        }
        for p in bundle.prompts {
            rows.append(
                Row(
                    table: "prompt", key: ["id": p.id, "version": p.version],
                    values: [
                        "role": p.role, "language": p.language, "template": p.template,
                        "output_schema_json": p.outputSchema.map(json),
                    ],
                    seedVersion: p.seedVersion))
        }
        for s in bundle.settings {
            rows.append(
                Row(
                    table: "setting", key: ["key": s.key], values: ["type": s.type, "value_json": json(s.value)],
                    seedVersion: s.seedVersion))
        }
        // Parents before children, so the parent reference always resolves.
        for k in parentsFirst(bundle.nodeKinds) {
            rows.append(
                Row(
                    table: "node_kind", key: ["id": k.id],
                    values: [
                        "name": k.name, "parent_id": k.parentID, "system": k.system, "style_json": json(k.style),
                        "enabled": k.enabled,
                    ],
                    seedVersion: k.seedVersion))
        }
        for k in bundle.edgeKinds {
            rows.append(
                Row(
                    table: "edge_kind", key: ["id": k.id],
                    values: [
                        "name": k.name, "system": k.system, "derived": k.derived, "directed": k.directed,
                        "from_kinds_json": json(k.fromKinds), "to_kinds_json": json(k.toKinds),
                        "style_json": json(k.style), "enabled": k.enabled,
                    ],
                    seedVersion: k.seedVersion))
        }
        return rows
    }
}

/// Node kinds ordered by depth below their root kind; a broken parent chain ends the walk (validation reports it).
private func parentsFirst(_ kinds: [SeedBundle.NodeKind]) -> [SeedBundle.NodeKind] {
    let parents = Dictionary(kinds.map { ($0.id, $0.parentID) }, uniquingKeysWith: { first, _ in first })
    func depth(_ id: String) -> Int {
        var depth = 0
        var current = parents[id] ?? nil
        var seen: Set<String> = [id]
        while let parent = current, seen.insert(parent).inserted {
            depth += 1
            current = parents[parent] ?? nil
        }
        return depth
    }
    return kinds.enumerated().sorted { (depth($0.element.id), $0.offset) < (depth($1.element.id), $1.offset) }
        .map(\.element)
}

/// Encodes a value as compact, key-sorted JSON text for a `*_json` column.
func json(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
}

/// Decodes a `*_json` column.
func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
}
