import Foundation

/// Builds a transcriber for a model, given the folder its files live in.
/// Engines register one of these under their engine key in the composition root.
public typealias TranscriberFactory = @Sendable (_ model: ModelConfig, _ modelDirectory: URL) throws -> any Transcriber

/// Builds a live preview for a model, with Vocabulary terms to pass as recognition context.
public typealias LivePreviewFactory =
    @Sendable (_ model: ModelConfig, _ vocabulary: [String]) throws -> any LivePreviewing

/// Builds an embedder for a model, given the folder its files live in.
public typealias EmbedderFactory = @Sendable (_ model: ModelConfig, _ modelDirectory: URL) throws -> any Embedder
