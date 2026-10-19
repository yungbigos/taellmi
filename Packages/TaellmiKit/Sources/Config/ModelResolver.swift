import Domain
import Foundation
import GRDB
import Persistence

/// Facts about the machine right now, used by assignment conditions.
public struct RuntimeConditions: Sendable, Equatable {
    public var onBattery: Bool

    public init(onBattery: Bool) {
        self.onBattery = onBattery
    }
}

public struct ResolutionError: Error, Equatable, CustomStringConvertible {
    public var role: ModelRole
    /// Why each candidate model was skipped, by model id.
    public var rejected: [String: String]

    public init(role: ModelRole, rejected: [String: String]) {
        self.role = role
        self.rejected = rejected
    }

    public var description: String {
        let reasons = rejected.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return "No usable model for \(role.rawValue). "
            + (reasons.isEmpty ? "Nothing assigned." : reasons.joined(separator: "; "))
    }
}

/// Picks the model for a role from the `assignment` table. Code never names models; it asks this.
///
/// Reads the database on every call, so config edits apply to the very next job.
public struct ModelResolver: Sendable {
    private let database: AppDatabase
    private let registeredEngines: Set<String>
    private let installation: ModelInstallation
    private let conditions: @Sendable () -> RuntimeConditions

    public init(
        database: AppDatabase, registeredEngines: Set<String>, installation: ModelInstallation,
        conditions: @escaping @Sendable () -> RuntimeConditions
    ) {
        self.database = database
        self.registeredEngines = registeredEngines
        self.installation = installation
        self.conditions = conditions
    }

    public func resolve(_ role: ModelRole) throws -> ModelConfig {
        let candidates = try database.reader.read { db in
            try GRDB.Row.fetchAll(
                db,
                sql: """
                    SELECT m.*, a.conditions_json, p.kind AS provider_kind
                    FROM assignment a
                    JOIN model m ON m.id = a.model_id
                    JOIN provider p ON p.id = m.provider_id
                    WHERE a.role = ? AND a.enabled AND m.enabled AND p.enabled
                    ORDER BY a.priority, a.id
                    """,
                arguments: [role.rawValue])
        }
        let now = conditions()
        var rejected: [String: String] = [:]
        for row in candidates {
            let model: ModelConfig
            do {
                model = try Self.model(from: row)
            } catch {
                rejected[row["id"] as String] = "config row is malformed"
                continue
            }
            if let reason = rejection(of: model, row: row, role: role, now: now) {
                rejected[model.id] = reason
                continue
            }
            return model
        }
        throw ResolutionError(role: role, rejected: rejected)
    }

    private func rejection(of model: ModelConfig, row: GRDB.Row, role: ModelRole, now: RuntimeConditions) -> String? {
        guard registeredEngines.contains(model.engine) else { return "engine \(model.engine) is not available" }
        guard model.capabilities.contains(role.rawValue) else { return "cannot do \(role.rawValue)" }
        let providerKind: String = row["provider_kind"]
        if providerKind != "apple_system", !installation.isInstalled(model) { return "not downloaded" }
        let conditionText: String = row["conditions_json"]
        guard let rules = try? decodeJSON([String: JSONValue].self, from: conditionText) else {
            return "assignment conditions are malformed"
        }
        if rules["power"]?.stringValue == "ac_only", now.onBattery { return "only runs on mains power" }
        return nil
    }

    private static func model(from row: GRDB.Row) throws -> ModelConfig {
        ModelConfig(
            id: row["id"], name: row["name"], engine: row["engine"], providerID: row["provider_id"],
            sourceRef: row["source_ref"], revision: row["revision"],
            files: try decodeJSON([ModelFile].self, from: row["files_json"]),
            params: try decodeJSON([String: JSONValue].self, from: row["params_json"]),
            capabilities: try decodeJSON([String].self, from: row["capabilities_json"]),
            estimatedMemoryMB: row["est_memory_mb"])
    }
}
