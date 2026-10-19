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

/// Keeps at most one heavy model loaded, and unloads it after it has been idle for the configured time.
public actor EngineCache<C: Clock>: TranscriberProvider where C.Duration == Duration {
    private let factories: [String: TranscriberFactory]
    private let installation: ModelInstallation
    private let clock: C
    private let idleUnload: @Sendable () -> Duration

    private var loadedConfig: ModelConfig?
    private var loaded: (any Transcriber)?
    private var inUse = 0
    private var lastReleased: C.Instant?

    public init(
        factories: [String: TranscriberFactory], installation: ModelInstallation, clock: C,
        idleUnload: @escaping @Sendable () -> Duration
    ) {
        self.factories = factories
        self.installation = installation
        self.clock = clock
        self.idleUnload = idleUnload
    }

    public var registeredEngines: Set<String> { Set(factories.keys) }

    public func acquire(_ model: ModelConfig) async throws -> any Transcriber {
        if let loadedConfig, loadedConfig != model {
            guard inUse == 0 else { throw EngineCacheError.busy(loadedModelID: loadedConfig.id) }
            await unloadCurrent()
        }
        guard let factory = factories[model.engine] else { throw EngineCacheError.unknownEngine(model.engine) }
        let transcriber: any Transcriber
        if let loaded {
            transcriber = loaded
        } else {
            transcriber = try factory(model, installation.directory(for: model))
            loaded = transcriber
            loadedConfig = model
        }
        inUse += 1
        return transcriber
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
