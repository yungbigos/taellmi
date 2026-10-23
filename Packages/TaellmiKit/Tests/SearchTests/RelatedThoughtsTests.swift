import Config
import Domain
import Foundation
import Persistence
import Search
import TestSupport
import Testing

@Suite("Thoughts related to a thought")
struct RelatedThoughtsTests {
    typealias Harness = HybridSearchTests.Harness

    private func related(_ harness: Harness) -> RelatedThoughts {
        RelatedThoughts(
            index: harness.index, fragments: FragmentStore(database: harness.database),
            vectors: VectorStore(database: harness.database),
            resolver: ModelResolver(
                database: harness.database, registeredEngines: ["fake_engine", "fake_embedder"],
                installation: ModelInstallation(root: harness.models.url),
                conditions: { RuntimeConditions(onBattery: false) }),
            settings: SettingsStore(database: harness.database))
    }

    @Test("the closest thoughts by meaning come first, never the thought itself, at most the configured number")
    func closestFirst() throws {
        let harness = try Harness()
        try harness.add("heizung", "Die Heizung in der Wohnung gluckert und wird nicht warm.")
        try harness.add("heizung2", "Heizung gluckert wieder, Wohnung bleibt kalt.")
        try harness.add("wohnung", "Die Wohnung ist kalt.")
        try harness.add("isar", "Mit Kim an der Isar spazieren.")
        try ConfigEditor(database: harness.database).setSetting(SettingKeys.relatedThoughtsCount, to: .number(2))

        let found = try related(harness).related(to: "heizung").map(\.id)
        #expect(found == ["heizung2", "wohnung"])
    }

    @Test("thoughts below the similarity threshold are not related")
    func threshold() throws {
        let harness = try Harness()
        try harness.add("heizung", "Die Heizung gluckert.")
        try harness.add("isar", "Mit Kim an der Isar spazieren.")
        #expect(try related(harness).related(to: "heizung").isEmpty)
    }

    @Test("a thought without vectors yet has no related thoughts")
    func noVectors() throws {
        let harness = try Harness()
        try harness.index.upsert(
            Entry(id: "x", createdAt: sampleDate, durationSeconds: nil, source: .typed, folder: "x", text: "Neu."),
            transcript: nil)
        #expect(try related(harness).related(to: "x").isEmpty)
    }

    @Test("a repeated question gets the same answer, and a new thought counts as soon as it has vectors")
    func cachedUntilVectorsChange() throws {
        let harness = try Harness()
        try harness.add("heizung", "Die Heizung in der Wohnung gluckert und wird nicht warm.")
        try harness.add("wohnung", "Die Wohnung ist kalt.")
        let related = related(harness)
        #expect(try related.related(to: "heizung").map(\.id) == ["wohnung"])
        #expect(try related.related(to: "heizung").map(\.id) == ["wohnung"])
        try harness.add("heizung2", "Heizung gluckert wieder, Wohnung bleibt kalt.")
        #expect(try related.related(to: "heizung").map(\.id).first == "heizung2")
    }
}
