import Config
import Domain
import Foundation
import Persistence
import Search

/// One configuration to measure: settings to apply on top of the defaults, and whether meaning search runs.
public struct EvalVariant: Sendable {
    public var name: String
    public var settings: [String: JSONValue]
    public var meaning: Bool

    public init(name: String, settings: [String: JSONValue] = [:], meaning: Bool = true) {
        self.name = name
        self.settings = settings
        self.meaning = meaning
    }
}

public struct EvalReport: Sendable {
    public var set: String
    public var variant: String
    public var passages: Int
    public var overall: EvalMetrics.Summary
    public var byKind: [(kind: String, summary: EvalMetrics.Summary)]
    public var millisecondsPerSearch: Double
    /// Similarity of the closest passage per search, split by whether the search has a right answer. Shows
    /// whether any fixed threshold can tell "something relevant" from "nothing relevant".
    public var bestSimilarity: (answerable: [Double], unanswerable: [Double]) = ([], [])
    /// How far the closest passage stands out: its similarity minus the average of the 20 closest.
    public var bestMargin: (answerable: [Double], unanswerable: [Double]) = ([], [])
}

/// Runs an evaluation set through the app's real indexing and search, on a scratch database.
public struct SearchEvaluator: Sendable {
    private let engines: Set<String>
    private let installation: ModelInstallation
    private let embedders: CachingEmbedderProvider
    private let scratch: URL
    private let seed: @Sendable (AppDatabase) throws -> Void

    /// `seed` fills a fresh database with config, including the embedding model to use.
    static let batchSize = 32
    private let progress: @Sendable (String) -> Void

    public init(
        engines: Set<String>, installation: ModelInstallation, embedders: any EmbedderProvider, scratch: URL,
        progress: @escaping @Sendable (String) -> Void = { _ in },
        seed: @escaping @Sendable (AppDatabase) throws -> Void
    ) {
        self.progress = progress
        self.engines = engines
        self.installation = installation
        self.embedders = CachingEmbedderProvider(wrapping: embedders)
        self.scratch = scratch
        self.seed = seed
    }

    public func run(_ set: EvalSet, variant: EvalVariant) async throws -> EvalReport {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let file = scratch.appendingPathComponent("eval-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: file.path + suffix))
            }
        }
        let database = try AppDatabase.open(at: file)
        // A throwaway database: skip the disk flush after every write, which otherwise dominates the run.
        try await database.writer.writeWithoutTransaction { try $0.execute(sql: "PRAGMA synchronous = OFF") }
        try seed(database)
        let editor = ConfigEditor(database: database)
        for (key, value) in variant.settings { try editor.setSetting(key, to: value) }
        let settings = SettingsStore(database: database)
        let resolver = ModelResolver(
            database: database, registeredEngines: engines, installation: installation,
            conditions: { RuntimeConditions(onBattery: false) })

        let index = EntryIndex(database: database)
        let fragments = FragmentStore(database: database)
        let vectors = VectorStore(database: database)
        let splitter = PassageSplitter(
            targetLength: Int(try settings.number(SettingKeys.fragmentTargetLength)),
            maxLength: Int(try settings.number(SettingKeys.fragmentMaxLength)))
        let model = variant.meaning ? try resolver.resolve(.embed) : nil
        var all: [StoredFragment] = []
        for document in set.documents {
            try index.upsert(
                Entry(
                    id: document.id, createdAt: document.date ?? Date(timeIntervalSince1970: 0), durationSeconds: nil,
                    source: .typed, folder: document.id, text: document.text),
                transcript: nil)
            all += try fragments.replace(
                entryID: document.id, spans: splitter.passages(in: document.text), sourceText: document.text,
                method: "eval")
        }
        if let model {
            // Large batches of similar length keep the GPU busy and padding small.
            let ordered = all.sorted { $0.text.utf16.count < $1.text.utf16.count }
            let embedder = try await embedders.acquireEmbedder(model)
            for start in stride(from: 0, to: ordered.count, by: Self.batchSize) {
                let batch = Array(ordered[start..<min(start + Self.batchSize, ordered.count)])
                let embedded = try await embedder.embed(batch.map(\.text), purpose: .document)
                try vectors.upsert(Array(zip(batch.map(\.id), embedded)), space: model.vectorSpace)
                progress("\(set.name) · \(variant.name): embedded \(start + batch.count)/\(ordered.count) passages")
            }
            await embedders.release(model)
        }
        let passages = all.count

        let search = HybridSearch(
            index: index, fragments: fragments, vectors: vectors, resolver: resolver,
            embedders: variant.meaning ? embedders : UnavailableEmbedders(), settings: settings)
        var outcomes: [(kind: String, outcome: EvalMetrics.Outcome)] = []
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            for query in set.queries {
                let results = try await search.search(EntryQuery(text: query.text)).map(\.id)
                outcomes.append((query.kind, .init(results: results, relevant: Set(query.relevant))))
            }
        }
        var best: (answerable: [Double], unanswerable: [Double]) = ([], [])
        var margin: (answerable: [Double], unanswerable: [Double]) = ([], [])
        if let model {
            let embedder = try await embedders.acquireEmbedder(model)
            for query in set.queries {
                guard let vector = try await embedder.embed([query.text], purpose: .query).first,
                    case let near = try vectors.nearest(to: vector, space: model.vectorSpace, limit: 20),
                    let top = near.first
                else { continue }
                let gap = top.similarity - near.map(\.similarity).reduce(0, +) / Double(near.count)
                if query.relevant.isEmpty {
                    best.unanswerable.append(top.similarity)
                    margin.unanswerable.append(gap)
                } else {
                    best.answerable.append(top.similarity)
                    margin.answerable.append(gap)
                }
            }
            await embedders.release(model)
        }
        let kinds = Set(outcomes.map(\.kind)).sorted()
        var report = EvalReport(
            set: set.name, variant: variant.name, passages: passages,
            overall: .init(outcomes: outcomes.map(\.outcome)),
            byKind: kinds.map { kind in (kind, .init(outcomes: outcomes.filter { $0.kind == kind }.map(\.outcome))) },
            millisecondsPerSearch: Double(elapsed.components.attoseconds) / 1e15 / Double(max(1, set.queries.count))
                + Double(elapsed.components.seconds) * 1000 / Double(max(1, set.queries.count)))
        report.bestSimilarity = best
        report.bestMargin = margin
        return report
    }
}

/// Words-only runs: meaning search is never available.
struct UnavailableEmbedders: EmbedderProvider {
    struct Unavailable: Error {}
    func acquireEmbedder(_ model: ModelConfig) async throws -> any Embedder { throw Unavailable() }
    func release(_ model: ModelConfig) async {}
}

/// Remembers every vector by text and purpose, so variants that only change search settings never embed
/// the same text twice.
final class CachingEmbedderProvider: EmbedderProvider {
    private let wrapped: any EmbedderProvider
    private let cache = EmbeddingCache()

    init(wrapping wrapped: any EmbedderProvider) {
        self.wrapped = wrapped
    }

    func acquireEmbedder(_ model: ModelConfig) async throws -> any Embedder {
        CachingEmbedder(wrapped: try await wrapped.acquireEmbedder(model), cache: cache, space: model.vectorSpace)
    }

    func release(_ model: ModelConfig) async {
        await wrapped.release(model)
    }
}

actor EmbeddingCache {
    private var vectors: [String: [Float]] = [:]

    func get(_ key: String) -> [Float]? { vectors[key] }
    func set(_ key: String, _ vector: [Float]) { vectors[key] = vector }
}

struct CachingEmbedder: Embedder {
    let wrapped: any Embedder
    let cache: EmbeddingCache
    let space: String

    func embed(_ texts: [String], purpose: EmbeddingPurpose) async throws -> [[Float]] {
        let keys = texts.map { "\(space)|\(purpose)|\($0)" }
        var result: [[Float]?] = []
        for key in keys { result.append(await cache.get(key)) }
        let missing = result.indices.filter { result[$0] == nil }
        if !missing.isEmpty {
            let fresh = try await wrapped.embed(missing.map { texts[$0] }, purpose: purpose)
            for (index, vector) in zip(missing, fresh) {
                result[index] = vector
                await cache.set(keys[index], vector)
            }
        }
        return result.compactMap { $0 }
    }

    func unload() async {
        await wrapped.unload()
    }
}
