import Config
import Domain
import Foundation
import Persistence

/// The fake embedding model `seedFakeTranscription` installs, run by the `fake_embedder` engine.
public let fakeEmbeddingModel = ModelConfig(
    id: "fake-embedder", name: "fake-embedder", engine: "fake_embedder", providerID: "local",
    capabilities: ["embed"])

/// Seeds a database with the bundled defaults plus a fake transcription model and a fake embedding model at
/// top priority, marked as installed, so pipeline tests run without real models.
public func seedFakeTranscription(
    _ database: AppDatabase, modelsRoot: URL, modelID: String = "fake-transcriber", languageModel: Bool = false
) throws -> ModelConfig {
    var bundle = try SeedBundle.bundled()
    bundle.providers.append(
        .init(id: "local", kind: "local_folder", name: "Local", baseURL: nil, enabled: true, seedVersion: 1))
    bundle.models.append(.init(id: modelID, engine: "fake_engine", capabilities: ["transcription"]))
    bundle.assignments.append(.init(id: "fake", role: "transcription", priority: 0, modelID: modelID))
    bundle.models.append(.init(id: fakeEmbeddingModel.id, engine: fakeEmbeddingModel.engine, capabilities: ["embed"]))
    bundle.assignments.append(.init(id: "fake-embed", role: "embed", priority: 0, modelID: fakeEmbeddingModel.id))
    if languageModel {
        // A fake language model for the summary and concepts roles at top priority.
        bundle.models.append(
            .init(
                id: fakeLanguageModelConfig.id, engine: FakeLanguageModel.engineKey,
                capabilities: ["summary", "entities"]))
        for role in ["summary", "entities"] {
            bundle.assignments.append(
                .init(id: "fake-\(role)", role: role, priority: 0, modelID: fakeLanguageModelConfig.id))
        }
    }
    _ = try Seeder(database: database).apply(bundle)
    if languageModel { try ModelInstallation(root: modelsRoot).markVerified(fakeLanguageModelConfig) }
    let model = ModelConfig(id: modelID, name: modelID, engine: "fake_engine", providerID: "local")
    try ModelInstallation(root: modelsRoot).markVerified(model)
    try ModelInstallation(root: modelsRoot).markVerified(fakeEmbeddingModel)
    return model
}

/// The fake language model `seedFakeLanguageModel` installs, run by `FakeLanguageModel`.
public let fakeLanguageModelConfig = ModelConfig(
    id: "fake-lm", name: "fake-lm", engine: FakeLanguageModel.engineKey, providerID: "local",
    capabilities: ["summary", "entities"])
