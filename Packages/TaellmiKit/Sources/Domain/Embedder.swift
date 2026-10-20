import Foundation

/// What a text is embedded for. Some models phrase a search query differently from a stored passage.
public enum EmbeddingPurpose: Sendable, Equatable {
    case query
    case document
}

/// Turns texts into vectors whose closeness reflects closeness in meaning. Implemented by engine adapters.
public protocol Embedder: Sendable {
    /// One unit-length vector per text, in the same order.
    func embed(_ texts: [String], purpose: EmbeddingPurpose) async throws -> [[Float]]
    /// Releases model memory. The next `embed` call loads the model again.
    func unload() async
}

/// Hands out embedders, sharing the one-heavy-model-at-a-time rule with every other model. Every
/// `acquireEmbedder` must be paired with a `release`.
public protocol EmbedderProvider: Sendable {
    func acquireEmbedder(_ model: ModelConfig) async throws -> any Embedder
    func release(_ model: ModelConfig) async
}
