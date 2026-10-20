import Config
import Domain
import Foundation

public enum EngineCacheError: Error, Equatable {
    case unknownEngine(String)
    /// Another model is loaded and still in use; only one heavy model runs at a time.
    case busy(loadedModelID: String)
}

/// Hands out transcribers for the pipeline.
public protocol TranscriberProvider: Sendable {
    func acquire(_ model: ModelConfig) async throws -> any Transcriber
    func release(_ model: ModelConfig) async
}

/// Keeps at most one heavy model loaded, whatever its kind, and unloads it after it has been idle for the
/// configured time.
public actor EngineCache<C: Clock>: TranscriberProvider, EmbedderProvider where C.Duration == Duration {
    private enum Loaded {
        case transcriber(any Transcriber)
        case embedder(any Embedder)

        func unload() async {
            switch self {
            case .transcriber(let engine): await engine.unload()
            case .embedder(let engine): await engine.unload()
            }
        }
    }

    private let factories: [String: TranscriberFactory]
    private let embedders: [String: EmbedderFactory]
    private let installation: ModelInstallation
    private let clock: C
    private let idleUnload: @Sendable () -> Duration

    private var loadedConfig: ModelConfig?
    private var loaded: Loaded?
    private var inUse = 0
    private var lastReleased: C.Instant?

    public init(
        factories: [String: TranscriberFactory], embedders: [String: EmbedderFactory] = [:],
        installation: ModelInstallation, clock: C, idleUnload: @escaping @Sendable () -> Duration
    ) {
        self.factories = factories
        self.embedders = embedders
        self.installation = installation
        self.clock = clock
        self.idleUnload = idleUnload
    }

    public nonisolated var registeredEngines: Set<String> { Set(factories.keys).union(embedders.keys) }

    public func acquire(_ model: ModelConfig) async throws -> any Transcriber {
        guard let factory = factories[model.engine] else { throw EngineCacheError.unknownEngine(model.engine) }
        let directory = installation.directory(for: model)
        guard case .transcriber(let engine) = try await load(model, { .transcriber(try factory(model, directory)) })
        else { throw giveBack(model) }
        return engine
    }

    public func acquireEmbedder(_ model: ModelConfig) async throws -> any Embedder {
        guard let factory = embedders[model.engine] else { throw EngineCacheError.unknownEngine(model.engine) }
        let directory = installation.directory(for: model)
        guard case .embedder(let engine) = try await load(model, { .embedder(try factory(model, directory)) })
        else { throw giveBack(model) }
        return engine
    }

    /// Undoes the use counted by `load` when the loaded engine is of the wrong kind.
    private func giveBack(_ model: ModelConfig) -> EngineCacheError {
        inUse = max(0, inUse - 1)
        return .unknownEngine(model.engine)
    }

    private func load(_ model: ModelConfig, _ make: () throws -> Loaded) async throws -> Loaded {
        // Unloading suspends, and another caller may load a model meanwhile, so check again after every wait.
        while let current = loadedConfig, current != model {
            guard inUse == 0 else { throw EngineCacheError.busy(loadedModelID: current.id) }
            await unloadCurrent()
        }
        // No suspension from here on: the check above still holds.
        let engine: Loaded
        if let loaded {
            engine = loaded
        } else {
            engine = try make()
            loaded = engine
            loadedConfig = model
        }
        inUse += 1
        return engine
    }

    public func release(_ model: ModelConfig) async {
        guard model == loadedConfig, inUse > 0 else { return }
        inUse -= 1
        if inUse == 0 { lastReleased = clock.now }
    }

    /// Unloads the current model if nobody is using it and it has been idle long enough.
    /// The app calls this periodically; tests call it after advancing a test clock.
    public func evictIdle() async {
        guard inUse == 0, let lastReleased, lastReleased.duration(to: clock.now) >= idleUnload() else { return }
        await unloadCurrent()
    }

    /// Unloads the current model right away if nobody is using it (e.g. under memory pressure).
    public func unloadIfIdle() async {
        guard inUse == 0 else { return }
        await unloadCurrent()
    }

    public func unloadCurrent() async {
        guard let current = loaded else { return }
        loaded = nil
        loadedConfig = nil
        lastReleased = nil
        inUse = 0
        await current.unload()
    }
}
