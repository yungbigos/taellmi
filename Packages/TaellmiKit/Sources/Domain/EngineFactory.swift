import Foundation

/// Builds a transcriber for a model, given the folder its files live in.
/// Engines register one of these under their engine key in the composition root.
public typealias TranscriberFactory = @Sendable (_ model: ModelConfig, _ modelDirectory: URL) throws -> any Transcriber
