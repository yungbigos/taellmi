import Config
import Domain
import Foundation
import Persistence

/// The thoughts closest in meaning to a thought, from the passage vectors already stored. Needs no model at
/// all, so it never waits: a thought without vectors yet simply has none.
public struct RelatedThoughts: Sendable {
    private let index: EntryIndex
    private let fragments: FragmentStore
    private let vectors: VectorStore
    private let resolver: ModelResolver
    private let settings: SettingsStore

    public init(
        index: EntryIndex, fragments: FragmentStore, vectors: VectorStore, resolver: ModelResolver,
        settings: SettingsStore
    ) {
        self.index = index
        self.fragments = fragments
        self.vectors = vectors
        self.resolver = resolver
        self.settings = settings
    }

    /// Other thoughts, ranked by their closest passage to any of this thought's passages.
    public func related(to entryID: String) throws -> [Entry] {
        guard let space = try? resolver.resolve(.embed).vectorSpace else { return [] }
        let limit = Int(try settings.number(SettingKeys.relatedThoughtsCount))
        let minimum = try settings.number(SettingKeys.searchMinSimilarity)
        let candidates = Int(try settings.number(SettingKeys.searchVectorCandidates))
        let own = try fragments.fragments(entryID: entryID)
        var best: [String: Double] = [:]
        for vector in try vectors.vectors(nodeIDs: own.map(\.id), space: space).values {
            let hits = try vectors.nearest(to: vector, space: space, limit: candidates)
                .filter { $0.similarity >= minimum }
            let owners = Dictionary(
                uniqueKeysWithValues: try fragments.fragments(ids: hits.map(\.nodeID)).map { ($0.id, $0.entryID) })
            for hit in hits {
                guard let owner = owners[hit.nodeID], owner != entryID else { continue }
                best[owner] = max(best[owner] ?? 0, hit.similarity)
            }
        }
        return try best.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(max(0, limit))
            .compactMap { try index.entry(id: $0.key) }
    }
}
