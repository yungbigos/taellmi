import Domain
import Foundation
import GRDB
import Persistence

/// A prompt row from config: its text with `{{name}}` placeholders and the shape of the answer.
public struct PromptTemplate: Sendable, Equatable {
    public var id: String
    public var version: Int
    public var template: String
    public var outputSchema: JSONValue?

    public init(id: String, version: Int, template: String, outputSchema: JSONValue?) {
        self.id = id
        self.version = version
        self.template = template
        self.outputSchema = outputSchema
    }

    /// How derived rows refer to it (`prompt_ref`).
    public var ref: String { "\(id)@\(version)" }

    public func render(_ values: [String: String]) -> String {
        values.reduce(template) { text, pair in text.replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value) }
    }
}

public enum PromptError: Error, Equatable {
    case missing(role: String)
}

/// Reads prompts. Editing a prompt means adding a higher version, which makes its outputs stale.
public struct PromptStore: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// The highest version of the prompt for a role.
    public func current(role: ModelRole) throws -> PromptTemplate {
        let row = try database.reader.read { db in
            try Row.fetchOne(
                db, sql: "SELECT * FROM prompt WHERE role = ? ORDER BY version DESC, id LIMIT 1",
                arguments: [role.rawValue])
        }
        guard let row else { throw PromptError.missing(role: role.rawValue) }
        let schema: String? = row["output_schema_json"]
        return PromptTemplate(
            id: row["id"], version: row["version"], template: row["template"],
            outputSchema: try schema.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) })
    }
}
