import Config
import Domain
import Foundation
import GRDB
import Persistence
import TestSupport
import Testing

@Suite("Choosing the model for a job")
struct ModelResolverTests {
    /// Two transcription models: "primary" (priority 1) and "fallback" (priority 2).
    private func setUp(
        primaryEngine: String = "fake_engine", primaryCapabilities: [String] = ["transcription"],
        primaryConditions: [String: JSONValue] = [:]
    ) throws -> (AppDatabase, TemporaryDirectory) {
        let database = try makeDatabase()
        var bundle = SeedBundle.empty
        bundle.providers = [
            .init(id: "local", kind: "local_folder", name: "Local", baseURL: nil, enabled: true, seedVersion: 1)
        ]
        bundle.models = [
            .init(id: "primary", engine: primaryEngine, capabilities: primaryCapabilities),
            .init(id: "fallback", engine: "fake_engine", capabilities: ["transcription"]),
        ]
        bundle.assignments = [
            .init(id: "a1", role: "transcription", priority: 1, modelID: "primary", conditions: primaryConditions),
            .init(id: "a2", role: "transcription", priority: 2, modelID: "fallback"),
        ]
        _ = try Seeder(database: database).apply(bundle)
        return (database, try TemporaryDirectory())
    }

    private func resolver(
        _ database: AppDatabase, _ models: TemporaryDirectory, installed: [String] = ["primary", "fallback"],
        onBattery: Bool = false
    ) throws -> ModelResolver {
        let installation = ModelInstallation(root: models.url)
        for id in installed {
            try installation.markVerified(ModelConfig(id: id, name: id, engine: "fake_engine", providerID: "local"))
        }
        return ModelResolver(
            database: database, registeredEngines: ["fake_engine"], installation: installation,
            conditions: { RuntimeConditions(onBattery: onBattery) })
    }

    @Test("the highest-priority usable model wins")
    func priorityWins() throws {
        let (database, models) = try setUp()
        #expect(try resolver(database, models).resolve(.transcription).id == "primary")
    }

    @Test(
        "an unusable primary falls back to the next model",
        arguments: [
            ("not installed", ["fallback"], "fake_engine", ["transcription"]),
            ("unknown engine", ["primary", "fallback"], "no_such_engine", ["transcription"]),
            ("missing capability", ["primary", "fallback"], "fake_engine", ["embed"]),
        ])
    func fallsBack(reason: String, installed: [String], engine: String, capabilities: [String]) throws {
        let (database, models) = try setUp(primaryEngine: engine, primaryCapabilities: capabilities)
        #expect(
            try resolver(database, models, installed: installed).resolve(.transcription).id == "fallback", "\(reason)")
    }

    @Test("an assignment limited to mains power is skipped on battery")
    func powerCondition() throws {
        let (database, models) = try setUp(primaryConditions: ["power": .string("ac_only")])
        #expect(try resolver(database, models, onBattery: true).resolve(.transcription).id == "fallback")
        #expect(try resolver(database, models, onBattery: false).resolve(.transcription).id == "primary")
    }

    @Test("no usable model throws an error that explains every rejection")
    func explainsFailure() throws {
        let (database, models) = try setUp()
        #expect {
            try resolver(database, models, installed: []).resolve(.transcription)
        } throws: { error in
            guard let error = error as? ResolutionError else { return false }
            return error.role == .transcription && error.rejected.keys.sorted() == ["fallback", "primary"]
        }
    }

    @Test("swapping the model in the database takes effect on the next resolve, without restart")
    func liveSwap() throws {
        let (database, models) = try setUp()
        let resolver = try resolver(database, models)
        #expect(try resolver.resolve(.transcription).id == "primary")

        try ConfigEditor(database: database).assign(.transcription, modelID: "fallback", priority: 0)

        #expect(try resolver.resolve(.transcription).id == "fallback")
    }

    @Test("a model counts as installed only for the pinned revision")
    func installationTracksRevision() throws {
        let models = try TemporaryDirectory()
        let installation = ModelInstallation(root: models.url)
        var model = ModelConfig(id: "m", name: "m", engine: "e", providerID: "huggingface", revision: "abc")
        #expect(!installation.isInstalled(model))
        try installation.markVerified(model)
        #expect(installation.isInstalled(model))
        model.revision = "def"
        #expect(!installation.isInstalled(model))
    }

    @Test("a model row with malformed params is skipped and the next assignment is used")
    func malformedModelFallsBack() throws {
        let (database, models) = try setUp()
        try database.writer.write { db in
            try db.execute(sql: "UPDATE model SET params_json = '[1, 2]' WHERE id = 'primary'")
        }
        #expect(try resolver(database, models).resolve(.transcription).id == "fallback")
    }

    @Test("an assignment with unreadable conditions is rejected rather than ignored")
    func unreadableConditionsReject() throws {
        let (database, models) = try setUp()
        try database.writer.write { db in
            try db.execute(sql: "UPDATE assignment SET conditions_json = '[\"ac_only\"]' WHERE id = 'a1'")
        }
        #expect(try resolver(database, models).resolve(.transcription).id == "fallback")
    }
}
