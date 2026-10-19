import Domain
import Foundation

/// The default config shipped with the app, read from `Resources/Seeds/*.json`.
public struct SeedBundle: Sendable, Equatable {
    public struct Provider: Sendable, Equatable, Codable {
        public var id: String
        public var kind: String
        public var name: String
        public var baseURL: String?
        public var enabled: Bool
        public var seedVersion: Int

        enum CodingKeys: String, CodingKey {
            case id, kind, name, enabled
            case baseURL = "base_url"
            case seedVersion = "seed_version"
        }

        public init(id: String, kind: String, name: String, baseURL: String?, enabled: Bool, seedVersion: Int) {
            self.id = id
            self.kind = kind
            self.name = name
            self.baseURL = baseURL
            self.enabled = enabled
            self.seedVersion = seedVersion
        }
    }

    public struct Model: Sendable, Equatable, Codable {
        public var id: String
        public var name: String
        public var engine: String
        public var providerID: String
        public var sourceRef: String?
        public var revision: String?
        public var files: [ModelFile]
        public var params: [String: JSONValue]
        public var capabilities: [String]
        public var estimatedMemoryMB: Int?
        public var license: String?
        public var enabled: Bool
        public var seedVersion: Int

        enum CodingKeys: String, CodingKey {
            case id, name, engine, revision, files, params, capabilities, license, enabled
            case providerID = "provider_id"
            case sourceRef = "source_ref"
            case estimatedMemoryMB = "est_memory_mb"
            case seedVersion = "seed_version"
        }

        public init(
            id: String, name: String? = nil, engine: String, providerID: String = "local", sourceRef: String? = nil,
            revision: String? = nil, files: [ModelFile] = [], params: [String: JSONValue] = [:],
            capabilities: [String], estimatedMemoryMB: Int? = nil, license: String? = nil, enabled: Bool = true,
            seedVersion: Int = 1
        ) {
            self.id = id
            self.name = name ?? id
            self.engine = engine
            self.providerID = providerID
            self.sourceRef = sourceRef
            self.revision = revision
            self.files = files
            self.params = params
            self.capabilities = capabilities
            self.estimatedMemoryMB = estimatedMemoryMB
            self.license = license
            self.enabled = enabled
            self.seedVersion = seedVersion
        }
    }

    public struct Assignment: Sendable, Equatable, Codable {
        public var id: String
        public var role: String
        public var priority: Int
        public var modelID: String
        public var conditions: [String: JSONValue]
        public var enabled: Bool
        public var seedVersion: Int

        enum CodingKeys: String, CodingKey {
            case id, role, priority, conditions, enabled
            case modelID = "model_id"
            case seedVersion = "seed_version"
        }

        public init(
            id: String, role: String, priority: Int, modelID: String, conditions: [String: JSONValue] = [:],
            enabled: Bool = true, seedVersion: Int = 1
        ) {
            self.id = id
            self.role = role
            self.priority = priority
            self.modelID = modelID
            self.conditions = conditions
            self.enabled = enabled
            self.seedVersion = seedVersion
        }
    }

    public struct PipelineStep: Sendable, Equatable, Codable {
        public var id: String
        public var step: String
        public var ordinal: Int
        public var role: String?
        public var conditions: [String: JSONValue]
        public var enabled: Bool
        public var seedVersion: Int

        enum CodingKeys: String, CodingKey {
            case id, step, ordinal, role, conditions, enabled
            case seedVersion = "seed_version"
        }
    }

    public struct Prompt: Sendable, Equatable, Codable {
        public var id: String
        public var version: Int
        public var role: String
        public var language: String
        public var template: String
        public var outputSchema: JSONValue?
        public var seedVersion: Int

        enum CodingKeys: String, CodingKey {
            case id, version, role, language, template
            case outputSchema = "output_schema"
            case seedVersion = "seed_version"
        }
    }

    public struct Setting: Sendable, Equatable, Codable {
        public var key: String
        public var type: String
        public var value: JSONValue
        public var seedVersion: Int

        enum CodingKeys: String, CodingKey {
            case key, type, value
            case seedVersion = "seed_version"
        }

        public init(key: String, type: String, value: JSONValue, seedVersion: Int) {
            self.key = key
            self.type = type
            self.value = value
            self.seedVersion = seedVersion
        }
    }

    public var providers: [Provider]
    public var models: [Model]
    public var assignments: [Assignment]
    public var pipeline: [PipelineStep]
    public var prompts: [Prompt]
    public var settings: [Setting]

    public static let empty = SeedBundle(
        providers: [], models: [], assignments: [], pipeline: [], prompts: [], settings: [])

    public var rowCount: Int {
        providers.count + models.count + assignments.count + pipeline.count + prompts.count + settings.count
    }

    /// Loads the seed files shipped inside the Config module.
    public static func bundled() throws -> SeedBundle {
        guard let folder = Bundle.module.url(forResource: "Seeds", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: folder)
    }

    public static func load(from folder: URL) throws -> SeedBundle {
        func read<T: Decodable>(_ name: String) throws -> [T] {
            let url = folder.appendingPathComponent("\(name).json")
            return try JSONDecoder().decode([T].self, from: Data(contentsOf: url))
        }
        return SeedBundle(
            providers: try read("providers"), models: try read("models"), assignments: try read("assignments"),
            pipeline: try read("pipeline"), prompts: try read("prompts"), settings: try read("settings"))
    }

    /// Problems that would make this config unusable. Empty means valid.
    public func validate() -> [String] {
        var problems: [String] = []
        let providerKinds = Dictionary(providers.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let modelIDs = Set(models.map(\.id))
        let roles = Set(ModelRole.allCases.map(\.rawValue))

        for model in models {
            guard let kind = providerKinds[model.providerID] else {
                problems.append("model \(model.id): unknown provider \(model.providerID)")
                continue
            }
            if kind == "huggingface" {
                if model.revision?.isEmpty ?? true { problems.append("model \(model.id): no pinned revision") }
                if model.files.isEmpty { problems.append("model \(model.id): no files listed") }
                for file in model.files where file.sha256.count != 64 {
                    problems.append("model \(model.id): file \(file.path) has no valid sha256")
                }
            }
        }
        for assignment in assignments {
            if !modelIDs.contains(assignment.modelID) {
                problems.append("assignment \(assignment.id): unknown model \(assignment.modelID)")
            }
            if !roles.contains(assignment.role) {
                problems.append("assignment \(assignment.id): unknown role \(assignment.role)")
            }
        }
        let assignedRoles = Set(assignments.filter(\.enabled).map(\.role))
        for step in pipeline where step.enabled {
            if let role = step.role, !assignedRoles.contains(role) {
                problems.append("pipeline step \(step.id): role \(role) has no assignment")
            }
        }
        for prompt in prompts where !roles.contains(prompt.role) {
            problems.append("prompt \(prompt.id): unknown role \(prompt.role)")
        }
        for (key, count) in Dictionary(settings.map { ($0.key, 1) }, uniquingKeysWith: +) where count > 1 {
            problems.append("setting \(key) is defined \(count) times")
        }
        return problems
    }
}
