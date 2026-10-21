import Config
import Domain
import Foundation
import Persistence
import os

/// Finds thoughts by their words, then related thoughts by their meaning.
///
/// Thoughts that contain every search word come first, ordered by Reciprocal Rank Fusion of keyword relevance
/// and meaning. Thoughts found only by meaning follow as related, closest first. The embedding model ranks
/// well but cannot tell "nothing relevant" from "something relevant" (docs/research/2026-10-search-eval.md),
/// so meaning alone never makes a thought an answer. Meaning search needs the embedding model; when it is not
/// installed or another model is busy, search answers with words alone instead of waiting.
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

    /// Thoughts in the order `hits` returns them.
    public func search(_ query: EntryQuery, now: Date = Date(), calendar: Calendar = .current) async throws
        -> [Entry]
    {
        try await hits(query, now: now, calendar: calendar).map(\.entry)
    }

    /// Newest first without search words; otherwise word matches, then related thoughts.
    public func hits(_ query: EntryQuery, now: Date = Date(), calendar: Calendar = .current) async throws
        -> [SearchHit]
    {
        let byWords = try index.search(query, now: now, calendar: calendar)
        guard !query.words.isEmpty else { return byWords.map { SearchHit(entry: $0, match: .words) } }
        let words = query.words

        let scores = try index.keywordScores(words: query.words)
        let keywordRanking = byWords.enumerated()
            .sorted { lhs, rhs in
                let left = scores[lhs.element.id] ?? -.infinity
                let right = scores[rhs.element.id] ?? -.infinity
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        let meaning = try await byMeaning(query, now: now, calendar: calendar)
        let meaningRanking = meaning.map(\.entry)

        let k = try settings.number(SettingKeys.searchRRFK)
        var fused: [String: (entry: Entry, score: Double)] = [:]
        for ranking in [keywordRanking, meaningRanking] {
            for (rank, entry) in ranking.enumerated() {
                fused[entry.id, default: (entry, 0)].score += 1 / (k + Double(rank + 1))
            }
        }
        let wordIDs = Set(byWords.map(\.id))
        let results = fused.values.filter { wordIDs.contains($0.entry.id) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.createdAt > $1.entry.createdAt }
            .map {
                SearchHit(entry: $0.entry, match: .words, wordRanges: TextMatch.sections(for: words, in: $0.entry.text))
            }
        let related = meaning.filter { !wordIDs.contains($0.entry.id) }.map {
            SearchHit(
                entry: $0.entry, match: .related, wordRanges: TextMatch.sections(for: words, in: $0.entry.text),
                passage: $0.passage)
        }
        return results + related
    }

    /// Entries with a passage close in meaning to the search text, closest first, with that passage. Empty when
    /// meaning search is not possible right now.
    private func byMeaning(_ query: EntryQuery, now: Date, calendar: Calendar) async throws
        -> [(entry: Entry, passage: Range<Int>)]
    {
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
        var hits = try vectors.nearest(
            to: vector, space: model.vectorSpace, limit: Int(try settings.number(SettingKeys.searchVectorCandidates))
        )
        .filter { $0.similarity >= minSimilarity }
        let window = try settings.number(SettingKeys.searchRelativeSimilarityWindow)
        if window > 0, let best = hits.first?.similarity {
            // A clear best match makes the weak tail noise, even above the fixed threshold.
            hits = hits.filter { $0.similarity >= best - window }
        }
        let fragmentOfID = Dictionary(
            try fragments.fragments(ids: hits.map(\.nodeID)).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })

        let earliest = query.earliestDate(now: now, calendar: calendar)
        var seen: Set<String> = []
        var ranking: [(entry: Entry, passage: Range<Int>)] = []
        for hit in hits {
            guard let fragment = fragmentOfID[hit.nodeID], seen.insert(fragment.entryID).inserted,
                let entry = try index.entry(id: fragment.entryID)
            else { continue }
            if let earliest, entry.createdAt < earliest { continue }
            if let sources = query.sources, !sources.contains(entry.source) { continue }
            ranking.append((entry, fragment.utf16Range))
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
