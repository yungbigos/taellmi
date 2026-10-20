import Config
import Domain
import Foundation
import Persistence
import os

/// Finds thoughts by their words and by their meaning, best match first.
///
/// Two rankings are merged with Reciprocal Rank Fusion: Entries that contain every search word (ordered by
/// keyword relevance), and Entries with a passage close in meaning to the search text. Meaning search needs
/// the embedding model; when it is not installed or another model is busy, search answers with words alone
/// instead of waiting.
public struct HybridSearch: Sendable {
    private let logger = Logger(subsystem: "app.taellmi", category: "search")
    private let index: EntryIndex
    private let fragments: FragmentStore
    private let vectors: VectorStore
    private let resolver: ModelResolver
    private let embedders: any EmbedderProvider
    private let settings: SettingsStore

    public init(
        index: EntryIndex, fragments: FragmentStore, vectors: VectorStore, resolver: ModelResolver,
        embedders: any EmbedderProvider, settings: SettingsStore
    ) {
        self.index = index
        self.fragments = fragments
        self.vectors = vectors
        self.resolver = resolver
        self.embedders = embedders
        self.settings = settings
    }

    public func search(_ query: EntryQuery, now: Date = Date(), calendar: Calendar = .current) async throws
        -> [Entry]
    {
        let byWords = try index.search(query, now: now, calendar: calendar)
        guard !query.words.isEmpty else { return byWords }

        let scores = try index.keywordScores(words: query.words)
        let keywordRanking = byWords.enumerated()
            .sorted { lhs, rhs in
                let left = scores[lhs.element.id] ?? -.infinity
                let right = scores[rhs.element.id] ?? -.infinity
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        let meaningRanking = try await byMeaning(query, now: now, calendar: calendar)

        let k = try settings.number(SettingKeys.searchRRFK)
        var fused: [String: (entry: Entry, score: Double)] = [:]
        for ranking in [keywordRanking, meaningRanking] {
            for (rank, entry) in ranking.enumerated() {
                fused[entry.id, default: (entry, 0)].score += 1 / (k + Double(rank + 1))
            }
        }
        return fused.values
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.createdAt > $1.entry.createdAt }
            .map(\.entry)
    }

    /// Entries with a passage close in meaning to the search text, closest first. Empty when meaning search
    /// is not possible right now.
    private func byMeaning(_ query: EntryQuery, now: Date, calendar: Calendar) async throws -> [Entry] {
        let model: ModelConfig
        let vector: [Float]
        do {
            model = try resolver.resolve(.embed)
            let embedder = try await embedders.acquireEmbedder(model)
            let result = await Result(catching: { try await embedder.embed([query.text], purpose: .query) })
            await embedders.release(model)
            guard let first = try result.get().first else { return [] }
            vector = first
        } catch {
            logger.info("Searching by words only: \(String(describing: error))")
            return []
        }

        let minSimilarity = try settings.number(SettingKeys.searchMinSimilarity)
        let hits = try vectors.nearest(
            to: vector, space: model.vectorSpace, limit: Int(try settings.number(SettingKeys.searchVectorCandidates))
        )
        .filter { $0.similarity >= minSimilarity }
        let entryOfFragment = Dictionary(
            try fragments.fragments(ids: hits.map(\.nodeID)).map { ($0.id, $0.entryID) },
            uniquingKeysWith: { first, _ in first })

        let earliest = query.earliestDate(now: now, calendar: calendar)
        var seen: Set<String> = []
        var ranking: [Entry] = []
        for hit in hits {
            guard let entryID = entryOfFragment[hit.nodeID], seen.insert(entryID).inserted,
                let entry = try index.entry(id: entryID)
            else { continue }
            if let earliest, entry.createdAt < earliest { continue }
            if let sources = query.sources, !sources.contains(entry.source) { continue }
            ranking.append(entry)
        }
        return ranking
    }
}

extension Result where Failure == any Error {
    fileprivate init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}
