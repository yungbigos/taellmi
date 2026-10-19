import Config
import Domain
import Foundation
import Persistence

/// Seeds a database with the bundled defaults plus one fake transcription model at top priority,
/// marked as installed, so pipeline tests run without real models.
public func seedFakeTranscription(
    _ database: AppDatabase, modelsRoot: URL, modelID: String = "fake-transcriber"
) throws -> ModelConfig {
    var bundle = try SeedBundle.bundled()
    bundle.providers.append(
        .init(id: "local", kind: "local_folder", name: "Local", baseURL: nil, enabled: true, seedVersion: 1))
    bundle.models.append(.init(id: modelID, engine: "fake_engine", capabilities: ["transcription"]))
    bundle.assignments.append(.init(id: "fake", role: "transcription", priority: 0, modelID: modelID))
    _ = try Seeder(database: database).apply(bundle)
    let model = ModelConfig(id: modelID, name: modelID, engine: "fake_engine", providerID: "local")
    try ModelInstallation(root: modelsRoot).markVerified(model)
    return model
}
