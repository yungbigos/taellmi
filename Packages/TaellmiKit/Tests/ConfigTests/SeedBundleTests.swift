import Config
import Domain
import Testing

@Suite("Bundled default config")
struct SeedBundleTests {
    @Test("the bundled seed files decode and have no validation problems")
    func bundledSeedsAreValid() throws {
        let bundle = try SeedBundle.bundled()
        #expect(bundle.validate() == [])
        #expect(!bundle.models.isEmpty)
    }

    @Test("every setting the code reads has a default in the seeds")
    func everySettingHasADefault() throws {
        let keys = Set(try SeedBundle.bundled().settings.map(\.key))
        for key in SettingKeys.all {
            #expect(keys.contains(key), "missing seed for setting \(key)")
        }
    }

    @Test("every seeded setting is one the code knows, so none is forgotten in SettingKeys.all")
    func noOrphanSettings() throws {
        let known = Set(SettingKeys.all)
        for setting in try SeedBundle.bundled().settings {
            #expect(known.contains(setting.key), "seed \(setting.key) is not in SettingKeys.all")
        }
    }

    @Test("validation catches a pipeline role with no assignment")
    func catchesUnassignedRole() throws {
        var bundle = try SeedBundle.bundled()
        bundle.assignments.removeAll()
        #expect(bundle.validate().contains { $0.contains("transcription") })
    }

    @Test("validation catches a downloadable model without file hashes")
    func catchesMissingHashes() throws {
        var bundle = try SeedBundle.bundled()
        bundle.models[0].files[0].sha256 = ""
        #expect(bundle.validate().contains { $0.contains("sha256") })
    }

    @Test("validation catches an assignment pointing at an unknown model")
    func catchesUnknownModel() throws {
        var bundle = try SeedBundle.bundled()
        bundle.assignments[0].modelID = "does-not-exist"
        #expect(bundle.validate().contains { $0.contains("does-not-exist") })
    }

    @Test("every graph kind the pipeline relies on is seeded and protected as a system kind")
    func systemKindsAreSeeded() throws {
        let bundle = try SeedBundle.bundled()
        let nodeKinds = Dictionary(uniqueKeysWithValues: bundle.nodeKinds.map { ($0.id, $0) })
        let edgeKinds = Dictionary(uniqueKeysWithValues: bundle.edgeKinds.map { ($0.id, $0) })
        for kind in GraphKinds.systemNodeKinds {
            #expect(nodeKinds[kind]?.system == true, "node kind \(kind) must be a seeded system kind")
        }
        for kind in GraphKinds.systemEdgeKinds {
            #expect(edgeKinds[kind]?.system == true, "edge kind \(kind) must be a seeded system kind")
        }
    }

    @Test("the four Concept kinds people, places, topics and feelings are seeded under concept")
    func conceptKindsAreSeeded() throws {
        let children = try SeedBundle.bundled().nodeKinds.filter { $0.parentID == GraphKinds.concept }.map(\.id)
        #expect(Set(children).isSuperset(of: ["person", "place", "topic", "emotion"]))
    }

    @Test("validation catches an edge kind that connects an unknown node kind")
    func catchesUnknownEdgeEndpoint() throws {
        var bundle = try SeedBundle.bundled()
        bundle.edgeKinds[0].fromKinds = ["does-not-exist"]
        #expect(bundle.validate().contains { $0.contains("does-not-exist") })
    }

    @Test("validation catches a missing system kind")
    func catchesMissingSystemKind() throws {
        var bundle = try SeedBundle.bundled()
        bundle.nodeKinds.removeAll { $0.id == GraphKinds.fragment }
        #expect(bundle.validate().contains { $0.contains(GraphKinds.fragment) })
    }
}
