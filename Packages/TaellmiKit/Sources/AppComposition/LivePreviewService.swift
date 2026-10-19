import Config
import Domain
import Foundation
import os

/// The live preview the capture screen uses: whatever model config assigns to `live_transcription`,
/// with the current Vocabulary as recognition context.
nonisolated struct LivePreviewService: LivePreviewing {
    let resolver: ModelResolver
    let factories: [String: LivePreviewFactory]
    let vocabulary: [any VocabularySource]
    private let logger = Logger(subsystem: "app.taellmi", category: "preview")

    init(resolver: ModelResolver, factories: [String: LivePreviewFactory], vocabulary: [any VocabularySource]) {
        self.resolver = resolver
        self.factories = factories
        self.vocabulary = vocabulary
    }

    func preview(_ audio: AsyncStream<AudioSamples>) async throws -> AsyncThrowingStream<LivePreview, any Error> {
        let model = try resolver.resolve(.liveTranscription)
        guard let factory = factories[model.engine] else {
            throw ResolutionError(
                role: .liveTranscription, rejected: [model.id: "engine \(model.engine) is not available"])
        }
        var terms: [String] = []
        for source in vocabulary {
            do {
                terms += try await source.terms().map(\.text)
            } catch {
                logger.error("A Vocabulary source failed: \(String(describing: error))")
            }
        }
        return try await factory(model, terms).preview(audio)
    }
}
