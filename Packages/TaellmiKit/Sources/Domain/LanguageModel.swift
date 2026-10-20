import Foundation

/// A local language model that fills a structured answer (ADR 0012). The answer always follows `schema`, a
/// JSON Schema subset from the prompt's config row, so callers never parse free text.
public protocol LanguageModel: Sendable {
    /// Whether the model can run on this Mac right now (e.g. Apple Intelligence is turned on).
    func availability() async -> LanguageModelAvailability
    /// Answers `prompt` with a JSON object that matches `schema`.
    func generate(prompt: String, schema: JSONValue) async throws -> JSONValue
    /// Releases what the model holds. The next call starts fresh.
    func unload() async
}

public enum LanguageModelAvailability: Sendable, Equatable {
    case available
    /// Why not, in words for the log (never shown as an error: the feature simply stays off).
    case unavailable(String)
}

public enum LanguageModelError: Error, Equatable {
    case unavailable(String)
    /// The prompt's output schema uses something the engine can't express.
    case unsupportedSchema(String)
    /// The thought is too long for the model's context.
    case inputTooLong
}

/// Builds a language model from its config row.
public typealias LanguageModelFactory = @Sendable (_ model: ModelConfig) throws -> any LanguageModel

/// Hands out language models by their config row.
public protocol LanguageModelProvider: Sendable {
    /// Engine keys this build can run, for the model resolver.
    var registeredEngines: Set<String> { get }
    func languageModel(_ model: ModelConfig) async throws -> any LanguageModel
}
