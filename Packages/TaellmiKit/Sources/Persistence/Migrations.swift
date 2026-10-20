import GRDB

/// Append-only schema history. Never edit a migration after it is committed; add a new one.
enum Migrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try createEntryTables(db)
            try createConfigTables(db)
        }
        migrator.registerMigration("v2_entry_search") { db in
            // Trigram index: finds parts of words ("angst" in "Zukunftsangst"). Text is stored lowercased.
            try db.execute(
                sql: "CREATE VIRTUAL TABLE entry_search USING fts5(entry_id UNINDEXED, text, tokenize = 'trigram')")
            try db.execute(sql: "INSERT INTO entry_search (entry_id, text) SELECT id, lower(text) FROM entry")
        }
        migrator.registerMigration("v3_graph") { db in
            try createGraphTables(db)
        }
        return migrator
    }

    /// The typed graph of ADR 0005. Kinds are config rows (seeded); nodes and edges are rebuildable.
    private static func createGraphTables(_ db: Database) throws {
        func provenance(_ t: TableDefinition) {
            t.column("origin", .text).notNull().defaults(to: "seed").check(sql: "origin IN ('seed', 'user')")
            t.column("seed_version", .integer).notNull().defaults(to: 0)
        }
        func json(_ t: TableDefinition, _ name: String) {
            t.column(name, .jsonText).check(sql: "\(name) IS NULL OR json_valid(\(name))")
        }
        func derivation(_ t: TableDefinition) {
            // How a row was made: an algorithm name with version, plus model and prompt when a model made it.
            t.column("method", .text).notNull()
            t.column("model_id", .text)
            t.column("prompt_ref", .text)
            t.column("created_at", .datetime)
        }

        try db.create(table: "node_kind") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("parent_id", .text).references("node_kind", onDelete: .setNull)
            t.column("system", .boolean).notNull().defaults(to: false)
            json(t, "style_json")
            t.column("enabled", .boolean).notNull().defaults(to: true)
            provenance(t)
        }
        try db.create(table: "edge_kind") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("system", .boolean).notNull().defaults(to: false)
            // Derived edges are recomputed; the others are hand-made and permanent.
            t.column("derived", .boolean).notNull()
            t.column("directed", .boolean).notNull().defaults(to: true)
            json(t, "from_kinds_json")
            json(t, "to_kinds_json")
            json(t, "style_json")
            t.column("enabled", .boolean).notNull().defaults(to: true)
            provenance(t)
        }
        for table in ["node_kind", "edge_kind"] {
            try db.execute(
                sql: """
                    CREATE TRIGGER \(table)_protect_system_delete BEFORE DELETE ON \(table) WHEN old.system
                    BEGIN SELECT RAISE(ABORT, 'system kinds cannot be deleted'); END;
                    CREATE TRIGGER \(table)_protect_system_flag BEFORE UPDATE OF system ON \(table)
                    WHEN old.system AND NOT new.system
                    BEGIN SELECT RAISE(ABORT, 'system kinds stay system kinds'); END;
                    """)
        }

        try db.create(table: "node") { t in
            t.primaryKey("id", .text)
            t.column("kind", .text).notNull().indexed().references("node_kind", onUpdate: .cascade)
            // The Entry this node was extracted from; nil for nodes across Entries (Concepts, Clusters).
            t.column("entry_id", .text).indexed().references("entry", onDelete: .cascade)
            t.column("ordinal", .integer)
            // Where the node's words sit in the Entry's Text, as UTF-16 offsets (what text views use).
            t.column("utf16_start", .integer)
            t.column("utf16_end", .integer)
            // A node's own words; for an entry node, the Text its Fragments were split from (to spot stale ones).
            t.column("text", .text)
            t.column("label", .text)
            json(t, "payload_json")
            derivation(t)
        }
        try db.create(table: "edge") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("kind", .text).notNull().indexed().references("edge_kind", onUpdate: .cascade)
            t.column("from_id", .text).notNull().indexed().references("node", onDelete: .cascade)
            t.column("to_id", .text).notNull().indexed().references("node", onDelete: .cascade)
            t.column("weight", .double).notNull().defaults(to: 1)
            json(t, "evidence_json")
            derivation(t)
            t.uniqueKey(["kind", "from_id", "to_id"])
        }
        // Which node has a vector in which vector space (model + size). The vectors themselves live in
        // sqlite-vec tables per size; this indexed table keeps "what is missing" a cheap query.
        try db.create(table: "vector_meta") { t in
            t.column("node_id", .text).notNull()
            t.column("space", .text).notNull().indexed()
            t.column("dimensions", .integer).notNull()
            t.primaryKey(["node_id", "space"])
        }
    }

    private static func createEntryTables(_ db: Database) throws {
        try db.create(table: "entry") { t in
            t.primaryKey("id", .text)
            t.column("created_at", .datetime).notNull().indexed()
            t.column("duration_s", .double)
            t.column("source", .text).notNull()
            t.column("title", .text)
            t.column("folder", .text).notNull().unique()
            t.column("text", .text).notNull().defaults(to: "")
            t.column("transcript_model_id", .text)
        }
        try db.create(table: "segment") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("entry_id", .text).notNull().indexed().references("entry", onDelete: .cascade)
            t.column("ordinal", .integer).notNull()
            t.column("start_ms", .integer).notNull()
            t.column("end_ms", .integer).notNull()
            t.column("text", .text).notNull()
            t.uniqueKey(["entry_id", "ordinal"])
        }
        try db.create(table: "job") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("entry_id", .text).notNull().indexed().references("entry", onDelete: .cascade)
            t.column("step", .text).notNull()
            t.column("state", .text).notNull()
                .check(sql: "state IN ('pending', 'running', 'done', 'failed')")
            t.column("attempts", .integer).notNull().defaults(to: 0)
            t.column("last_error", .text)
            t.column("not_before", .datetime)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.uniqueKey(["entry_id", "step"])
        }
    }

    private static func createConfigTables(_ db: Database) throws {
        func provenance(_ t: TableDefinition) {
            t.column("origin", .text).notNull().defaults(to: "seed").check(sql: "origin IN ('seed', 'user')")
            t.column("seed_version", .integer).notNull().defaults(to: 0)
        }
        func json(_ t: TableDefinition, _ name: String, notNull: Bool = true) {
            let column = t.column(name, .jsonText).check(sql: "\(name) IS NULL OR json_valid(\(name))")
            if notNull { column.notNull() }
        }

        try db.create(table: "provider") { t in
            t.primaryKey("id", .text)
            t.column("kind", .text).notNull()
                .check(sql: "kind IN ('huggingface', 'local_folder', 'apple_system', 'openai_compatible_local')")
            t.column("name", .text).notNull()
            t.column("base_url", .text)
            t.column("enabled", .boolean).notNull().defaults(to: true)
            provenance(t)
        }
        try db.create(table: "model") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("engine", .text).notNull()
            t.column("provider_id", .text).notNull().indexed().references("provider")
            t.column("source_ref", .text)
            t.column("revision", .text)
            json(t, "files_json")
            json(t, "params_json")
            json(t, "capabilities_json")
            t.column("est_memory_mb", .integer)
            t.column("license", .text)
            t.column("enabled", .boolean).notNull().defaults(to: true)
            provenance(t)
        }
        try db.create(table: "assignment") { t in
            t.primaryKey("id", .text)
            t.column("role", .text).notNull().indexed()
            t.column("priority", .integer).notNull()
            t.column("model_id", .text).notNull().indexed().references("model", onDelete: .cascade)
            json(t, "conditions_json")
            t.column("enabled", .boolean).notNull().defaults(to: true)
            provenance(t)
        }
        try db.create(table: "prompt") { t in
            t.column("id", .text).notNull()
            t.column("version", .integer).notNull()
            t.column("role", .text).notNull()
            t.column("language", .text).notNull()
            t.column("template", .text).notNull()
            json(t, "output_schema_json", notNull: false)
            provenance(t)
            t.primaryKey(["id", "version"])
        }
        try db.create(table: "pipeline_step") { t in
            t.primaryKey("id", .text)
            t.column("step", .text).notNull()
            t.column("ordinal", .integer).notNull()
            t.column("role", .text)
            json(t, "conditions_json")
            t.column("enabled", .boolean).notNull().defaults(to: true)
            provenance(t)
        }
        try db.create(table: "setting") { t in
            t.primaryKey("key", .text)
            t.column("type", .text).notNull().check(sql: "type IN ('string', 'number', 'bool', 'json')")
            json(t, "value_json")
            provenance(t)
        }
    }
}
