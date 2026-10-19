import Domain
import Foundation
import GRDB
import Persistence

/// One enabled processing step, as configured in `pipeline_step`.
public struct PipelineStepConfig: Sendable, Equatable {
    public var id: String
    public var step: String
    public var role: ModelRole?

    public init(id: String, step: String, role: ModelRole?) {
        self.id = id
        self.step = step
        self.role = role
    }
}

public struct PipelineConfig: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Enabled steps in the order they run.
    public func enabledSteps() throws -> [PipelineStepConfig] {
        try database.reader.read { db in
            try GRDB.Row.fetchAll(
                db, sql: "SELECT id, step, role FROM pipeline_step WHERE enabled ORDER BY ordinal, id"
            ).map { row in
                PipelineStepConfig(
                    id: row["id"], step: row["step"], role: (row["role"] as String?).flatMap(ModelRole.init(rawValue:)))
            }
        }
    }
}
