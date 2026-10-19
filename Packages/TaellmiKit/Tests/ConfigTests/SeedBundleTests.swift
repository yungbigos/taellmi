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
}
