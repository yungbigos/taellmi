import Domain
import Foundation

/// Hands out one `FakeEmbedder`, or refuses while "busy" (another heavy model in use).
public actor FakeEmbedderProvider: EmbedderProvider {
    public struct Busy: Error {}

    public let embedder: FakeEmbedder
    public var isBusy = false
    public private(set) var released = 0

    public init(embedder: FakeEmbedder = FakeEmbedder()) {
        self.embedder = embedder
    }

    public func setBusy(_ busy: Bool) {
        isBusy = busy
    }

    public func acquireEmbedder(_ model: ModelConfig) async throws -> any Embedder {
        if isBusy { throw Busy() }
        return embedder
    }

    public func release(_ model: ModelConfig) async {
        released += 1
    }
}
