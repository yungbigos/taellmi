import Config
import Domain
import Foundation
import Persistence
import Synchronization
import TestSupport
import Testing

@testable import AppComposition

@Suite("Live preview chosen by config")
struct LivePreviewServiceTests {
    @Test("uses the model assigned to live transcription and passes the Vocabulary as context")
    func resolvesFromConfig() async throws {
        let database = try makeDatabase()
        _ = try Seeder(database: database).apply(SeedBundle.bundled())
        let seen = Recorded()
        let service = LivePreviewService(
            resolver: ModelResolver(
                database: database, registeredEngines: ["apple_speech"],
                installation: ModelInstallation(root: try TemporaryDirectory().url),
                conditions: { RuntimeConditions(onBattery: false) }),
            factories: [
                "apple_speech": { model, vocabulary in
                    seen.set(model.id, vocabulary)
                    return FakeLivePreview()
                }
            ],
            vocabulary: [FakeVocabularySource(["Kim"])])

        let (audio, feed) = AsyncStream.makeStream(of: AudioSamples.self)
        feed.finish()
        _ = try await service.preview(audio)

        #expect(seen.value?.model == "apple-speech-de")
        #expect(seen.value?.vocabulary == ["Kim"])
    }

    @Test("without a usable model the preview reports why, so capture can carry on without it")
    func noModel() async throws {
        let database = try makeDatabase()
        _ = try Seeder(database: database).apply(SeedBundle.bundled())
        let service = LivePreviewService(
            resolver: ModelResolver(
                database: database, registeredEngines: [],
                installation: ModelInstallation(root: try TemporaryDirectory().url),
                conditions: { RuntimeConditions(onBattery: false) }),
            factories: [:], vocabulary: [])
        let (audio, _) = AsyncStream.makeStream(of: AudioSamples.self)
        await #expect(throws: ResolutionError.self) { _ = try await service.preview(audio) }
    }
}

nonisolated final class Recorded: Sendable {
    private let storage = Mutex<(model: String, vocabulary: [String])?>(nil)
    func set(_ model: String, _ vocabulary: [String]) { storage.withLock { $0 = (model, vocabulary) } }
    var value: (model: String, vocabulary: [String])? { storage.withLock { $0 } }
}
