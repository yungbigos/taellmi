import Domain

/// Engine options read from a model's `params` in config, so a new embedding model of a supported
/// architecture is a config change.
public struct MLXEmbedderOptions: Sendable, Equatable {
    public enum Error: Swift.Error, Equatable {
        case missingParam(String)
        case invalidDimensions(Int)
        case unknownPooling(String)
        /// A query template must say where the query goes.
        case templateWithoutQuery
    }

    /// How token vectors become one vector per text.
    public enum PoolingKind: String, Sendable {
        case last, mean, cls, first
    }

    static let queryPlaceholder = "{{query}}"

    /// Vectors are cut to this size, then normalised (Matryoshka models keep their quality when cut).
    public let dimensions: Int
    public let pooling: PoolingKind
    let queryTemplate: String?
    /// Caps on MLX's GPU buffer cache and on its total memory. Without them the cache keeps every buffer it
    /// ever used and grows without bound over a long run.
    public let cacheLimitBytes: Int?
    public let memoryLimitBytes: Int?

    public init(params: [String: JSONValue]) throws {
        guard let size = params["dimensions"]?.doubleValue else { throw Error.missingParam("dimensions") }
        guard size >= 1 else { throw Error.invalidDimensions(Int(size)) }
        dimensions = Int(size)
        guard let poolingName = params["pooling"]?.stringValue else { throw Error.missingParam("pooling") }
        guard let pooling = PoolingKind(rawValue: poolingName) else { throw Error.unknownPooling(poolingName) }
        self.pooling = pooling
        cacheLimitBytes = params["cache_limit_mb"]?.doubleValue.map { Int($0) * 1024 * 1024 }
        memoryLimitBytes = params["memory_limit_mb"]?.doubleValue.map { Int($0) * 1024 * 1024 }
        queryTemplate = params["query_template"]?.stringValue
        if let queryTemplate, !queryTemplate.contains(Self.queryPlaceholder) { throw Error.templateWithoutQuery }
    }

    /// The text the model sees: queries in the configured phrasing, passages as they are.
    public func text(_ text: String, for purpose: EmbeddingPurpose) -> String {
        guard purpose == .query, let queryTemplate else { return text }
        return queryTemplate.replacingOccurrences(of: Self.queryPlaceholder, with: text)
    }
}
