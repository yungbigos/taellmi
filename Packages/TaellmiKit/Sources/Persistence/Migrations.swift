import GRDB

/// Append-only schema history. Never edit a migration after it is committed; add a new one.
enum Migrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try createEntryTables(db)
            try createConfigTables(db)
        }
        return migrator
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
