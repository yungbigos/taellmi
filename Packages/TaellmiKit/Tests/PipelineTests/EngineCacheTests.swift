import Clocks
import Config
import Domain
import Foundation
import Pipeline
import Synchronization
import TestSupport
import Testing

@Suite("Engine lifecycle")
struct EngineCacheTests {
    private let model = ModelConfig(id: "fake-transcriber", name: "Fake", engine: "fake_engine", providerID: "local")

    private func makeCache(clock: TestClock<Duration>, fake: FakeTranscriber) throws -> (
        EngineCache<TestClock<Duration>>, Counter
    ) {
        let created = Counter()
        let cache = EngineCache(
            factories: [
                "fake_engine": { _, _ in
                    created.increment()
                    return fake
                }
            ],
            installation: ModelInstallation(root: try TemporaryDirectory().url),
            clock: clock, idleUnload: { .seconds(60) })
        return (cache, created)
    }

    @Test("the same model is loaded once and reused")
    func reuses() async throws {
        let fake = FakeTranscriber()
        let (cache, created) = try makeCache(clock: TestClock(), fake: fake)
        _ = try await cache.acquire(model)
        await cache.release(model)
        _ = try await cache.acquire(model)
        #expect(created.value == 1)
    }

    @Test("an idle model is unloaded after the configured time, not before")
    func unloadsWhenIdle() async throws {
        let clock = TestClock()
        let fake = FakeTranscriber()
        let (cache, _) = try makeCache(clock: clock, fake: fake)
        _ = try await cache.acquire(model)
        await cache.release(model)

        await clock.advance(by: .seconds(59))
        await cache.evictIdle()
        #expect(await fake.unloadCalls == 0)

        await clock.advance(by: .seconds(1))
        await cache.evictIdle()
        #expect(await fake.unloadCalls == 1)
    }

    @Test("a model in use is never unloaded")
    func keepsBusyModel() async throws {
        let clock = TestClock()
        let fake = FakeTranscriber()
        let (cache, _) = try makeCache(clock: clock, fake: fake)
        _ = try await cache.acquire(model)
        await clock.advance(by: .seconds(600))
        await cache.evictIdle()
        #expect(await fake.unloadCalls == 0)
    }

    @Test("switching to another model unloads the previous one first (one heavy model at a time)")
    func oneAtATime() async throws {
        let fake = FakeTranscriber()
        let (cache, _) = try makeCache(clock: TestClock(), fake: fake)
        _ = try await cache.acquire(model)
        await cache.release(model)
        var other = model
        other.id = "other"
        _ = try await cache.acquire(other)
        #expect(await fake.unloadCalls == 1)
    }

    @Test("an unknown engine is a clear error")
    func unknownEngine() async throws {
        let (cache, _) = try makeCache(clock: TestClock(), fake: FakeTranscriber())
        var broken = model
        broken.engine = "nope"
        await #expect(throws: EngineCacheError.unknownEngine("nope")) {
            _ = try await cache.acquire(broken)
        }
    }

    @Test("under memory pressure an idle model is unloaded at once, a busy one is kept")
    func memoryPressure() async throws {
        let fake = FakeTranscriber()
        let (cache, _) = try makeCache(clock: TestClock(), fake: fake)
        _ = try await cache.acquire(model)
        await cache.unloadIfIdle()
        #expect(await fake.unloadCalls == 0)
        await cache.release(model)
        await cache.unloadIfIdle()
        #expect(await fake.unloadCalls == 1)
    }

    @Test("a model that is in use is never swapped out for another one")
    func busyModelIsNotSwapped() async throws {
        let fake = FakeTranscriber()
        let (cache, _) = try makeCache(clock: TestClock(), fake: fake)
        _ = try await cache.acquire(model)
        var other = model
        other.id = "other"
        await #expect(throws: EngineCacheError.busy(loadedModelID: model.id)) {
            _ = try await cache.acquire(other)
        }
        #expect(await fake.unloadCalls == 0)
    }

    @Test("changed config for the loaded model reloads it on the next use")
    func configChangeReloads() async throws {
        let fake = FakeTranscriber()
        let (cache, created) = try makeCache(clock: TestClock(), fake: fake)
        _ = try await cache.acquire(model)
        await cache.release(model)
        var changed = model
        changed.params = ["version": .string("v9")]
        _ = try await cache.acquire(changed)
        #expect(created.value == 2)
        #expect(await fake.unloadCalls == 1)
    }

    @Test("transcriber and embedder share the one-heavy-model rule: loading one unloads the other")
    func embedderSharesTheSlot() async throws {
        let transcriber = FakeTranscriber()
        let embedder = FakeEmbedder()
        let cache = EngineCache(
            factories: ["fake_engine": { _, _ in transcriber }],
            embedders: ["fake_embedder": { _, _ in embedder }],
            installation: ModelInstallation(root: try TemporaryDirectory().url), clock: TestClock(),
            idleUnload: { .seconds(60) })
        let embedModel = ModelConfig(id: "fake-embedder", name: "Fake", engine: "fake_embedder", providerID: "local")

        _ = try await cache.acquire(model)
        await cache.release(model)
        _ = try await cache.acquireEmbedder(embedModel)
        #expect(await transcriber.unloadCalls == 1)
        await cache.release(embedModel)
        _ = try await cache.acquire(model)
        #expect(await embedder.unloadCalls == 1)
    }

    @Test("asking for an embedder from a transcription engine is a clear error")
    func wrongEngineKind() async throws {
        let (cache, _) = try makeCache(clock: TestClock(), fake: FakeTranscriber())
        await #expect(throws: EngineCacheError.unknownEngine("fake_engine")) {
            _ = try await cache.acquireEmbedder(model)
        }
    }

    @Test("a model loaded by someone else while the old one was unloading never leaves the cache stuck busy")
    func overlappingRequests() async throws {
        let slow = GatedUnloadTranscriber()
        let embedder = FakeEmbedder()
        let cache = EngineCache(
            factories: ["fake_engine": { _, _ in slow }], embedders: ["fake_embedder": { _, _ in embedder }],
            installation: ModelInstallation(root: try TemporaryDirectory().url), clock: TestClock(),
            idleUnload: { .seconds(60) })
        let embedModel = ModelConfig(id: "fake-embedder", name: "Fake", engine: "fake_embedder", providerID: "local")
        _ = try await cache.acquire(model)
        await cache.release(model)

        // Search asks for the embedder, which starts unloading the transcriber and waits there…
        let search = Task { try await cache.acquireEmbedder(embedModel) }
        await slow.waitUntilUnloadStarted()
        // …meanwhile the pipeline loads the transcriber again.
        _ = try await cache.acquire(model)
        await slow.finishUnload()
        await #expect(throws: EngineCacheError.busy(loadedModelID: model.id)) { _ = try await search.value }

        await cache.release(model)
        _ = try await cache.acquireEmbedder(embedModel)
    }
}

/// A transcriber whose unload waits until the test lets it finish.
actor GatedUnloadTranscriber: Transcriber {
    private var started: [CheckedContinuation<Void, Never>] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func transcribe(audioFile: URL) async throws -> RawTranscription { FakeTranscriber.germanResult }

    func unload() async {
        guard !hasStarted else { return }
        hasStarted = true
        for waiter in started { waiter.resume() }
        started = []
        await withCheckedContinuation { gate = $0 }
    }

    func waitUntilUnloadStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { started.append($0) }
    }

    func finishUnload() {
        gate?.resume()
        gate = nil
    }
}

/// Thread-safe counter for factory calls.
final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}
