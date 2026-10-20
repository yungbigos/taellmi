import Domain
import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon
import Tokenizers

/// Runs MLX embedding models (Qwen3-Embedding and the other architectures MLXEmbedders knows) from a local
/// folder. Loads on first use; never downloads anything.
public actor MLXEmbedder: Embedder {
    public static let engineKey = "mlx_embedder"

    public static let factory: EmbedderFactory = { model, directory in
        MLXEmbedder(directory: directory, options: try MLXEmbedderOptions(params: model.params))
    }

    private let directory: URL
    private let options: MLXEmbedderOptions
    private var container: EmbedderModelContainer?
    /// The load in progress, so requests arriving meanwhile wait for it instead of loading the model again.
    private var loading: Task<EmbedderModelContainer, any Error>?
    /// Bumped by `unload()`, so a load that finishes after an unload is used once but not kept in memory.
    private var generation = 0

    /// Points MLX at Metal shaders built by Xcode, for command-line tools and tests that `swift build` made.
    /// Apps built by Xcode find their bundled shaders without this.
    public static func useMetalShaders(at file: URL) {
        GPU.metallib = file
    }

    public init(directory: URL, options: MLXEmbedderOptions) {
        self.directory = directory
        self.options = options
    }

    public func embed(_ texts: [String], purpose: EmbeddingPurpose) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let container = try await loaded()
        let inputs = texts.map { options.text($0, for: purpose) }
        let dimensions = options.dimensions
        let strategy = Self.strategy(options.pooling)
        return await container.perform { context in
            let tokenizer = context.tokenizer
            var ids = inputs.map { tokenizer.encode(text: $0, addSpecialTokens: true) }
            if let limit = context.model.maxPositionEmbeddings {
                ids = ids.map { $0.count > limit ? Array($0.suffix(limit)) : $0 }
            }
            let length = max(1, ids.map(\.count).max() ?? 1)
            let pad = Int32(tokenizer.eosTokenId ?? 0)
            // Right padding with a mask built from the lengths: the pad id can equal the end token that
            // last-token pooling reads, so the mask must not be derived from the ids.
            let tokens = stacked(
                ids.map { MLXArray($0.map(Int32.init) + Array(repeating: pad, count: length - $0.count)) })
            let mask = stacked(
                ids.map {
                    MLXArray(
                        Array(repeating: Int32(1), count: $0.count) + Array(repeating: 0, count: length - $0.count))
                })
            let output = context.model(tokens, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
            let pooled = Pooling(strategy: strategy, dimension: dimensions)(
                output, mask: mask, normalize: true, applyLayerNorm: false)
            pooled.eval()
            return (0..<pooled.dim(0)).map { pooled[$0].asArray(Float.self) }
        }
    }

    public func unload() async {
        generation += 1
        container = nil
        loading = nil
        Memory.clearCache()
    }

    private func loaded() async throws -> EmbedderModelContainer {
        if let container { return container }
        if let loading { return try await loading.value }
        // Process-wide in MLX; fine, because only one heavy model is loaded at a time.
        if let limit = options.cacheLimitBytes { Memory.cacheLimit = limit }
        if let limit = options.memoryLimitBytes { Memory.memoryLimit = limit }
        let directory = directory
        let task = Task {
            try await EmbedderModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
        }
        let started = generation
        loading = task
        let loaded: EmbedderModelContainer
        do {
            loaded = try await task.value
        } catch {
            if started == generation { loading = nil }  // a failed load is tried again next time
            throw error
        }
        guard started == generation else { return loaded }
        loading = nil
        container = loaded
        return loaded
    }

    private static func strategy(_ kind: MLXEmbedderOptions.PoolingKind) -> Pooling.Strategy {
        switch kind {
        case .last: .last
        case .mean: .mean
        case .cls: .cls
        case .first: .first
        }
    }
}

/// Reads the tokenizer from the model's own folder (tokenizer.json and its config); no Hub access.
struct LocalTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerAdapter(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

/// Bridges swift-transformers' tokenizer to the protocol MLX expects.
struct TokenizerAdapter: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        throw MLXLMCommon.TokenizerError.missingChatTemplate
    }
}
