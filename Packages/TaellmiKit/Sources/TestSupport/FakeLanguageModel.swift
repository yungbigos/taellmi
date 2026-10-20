import Domain
import Foundation

/// Answers the concepts and summary prompts with fixed results, and records what it was asked.
public actor FakeLanguageModel: LanguageModel, LanguageModelProvider {
    public static let engineKey = "fake_lm"

    public var concepts: [(name: String, kind: String, mention: String)]
    public var summary: String
    public var isAvailable: Bool
    public private(set) var prompts: [String] = []

    public init(
        concepts: [(name: String, kind: String, mention: String)] = [], summary: String = "Eine Zusammenfassung.",
        isAvailable: Bool = true
    ) {
        self.concepts = concepts
        self.summary = summary
        self.isAvailable = isAvailable
    }

    public func setAvailable(_ available: Bool) { isAvailable = available }

    /// Summary requests fail, like a model refusing a sensitive topic.
    public func declineSummaries() { declinesSummaries = true }
    private var declinesSummaries = false

    public nonisolated var registeredEngines: Set<String> { [Self.engineKey] }
    public func languageModel(_ model: ModelConfig) async throws -> any LanguageModel { self }

    public func availability() async -> LanguageModelAvailability {
        isAvailable ? .available : .unavailable("Apple Intelligence is off")
    }

    public func generate(prompt: String, schema: JSONValue) async throws -> JSONValue {
        guard isAvailable else { throw LanguageModelError.unavailable("Apple Intelligence is off") }
        prompts.append(prompt)
        let keys = schema.objectValue?["properties"]?.objectValue?.keys.map { $0 } ?? []
        if keys.contains("summary") {
            if declinesSummaries { throw CocoaError(.featureUnsupported) }
            return .object(["summary": .string(summary)])
        }
        return .object([
            "concepts": .array(
                concepts.map {
                    .object(["name": .string($0.name), "kind": .string($0.kind), "mention": .string($0.mention)])
                })
        ])
    }

    public func unload() async {}
}
