import Domain
import Foundation
import GRDB
import Persistence

/// Changes config on the user's behalf. Every row it touches becomes `origin = 'user'`,
/// so later seed upgrades leave it alone.
public struct ConfigEditor: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func setSetting(_ key: String, to value: JSONValue) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE setting SET value_json = ?, origin = 'user' WHERE key = ?", arguments: [json(value), key])
            guard db.changesCount == 1 else { throw SettingsError.missing(key) }
        }
    }

    /// Puts `modelID` on `role` at `priority` (lower wins). Existing assignments stay as fallbacks.
    public func assign(_ role: ModelRole, modelID: String, priority: Int) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO assignment (id, role, priority, model_id, conditions_json, enabled, origin, seed_version)
                    VALUES (?, ?, ?, ?, '{}', 1, 'user', 0)
                    ON CONFLICT(id) DO UPDATE SET priority = excluded.priority, enabled = 1, origin = 'user'
                    """,
                arguments: ["user-\(role.rawValue)-\(modelID)", role.rawValue, priority, modelID])
        }
    }
}
