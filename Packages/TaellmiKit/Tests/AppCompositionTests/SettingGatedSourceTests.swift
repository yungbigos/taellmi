import Config
import Domain
import TestSupport
import Testing

@testable import AppComposition

@Suite("Contacts as an opt-in Vocabulary source")
struct SettingGatedSourceTests {
    @Test("contributes nothing until the setting is turned on")
    func optIn() async throws {
        let database = try makeDatabase()
        _ = try Seeder(database: database).apply(SeedBundle.bundled())
        let source = SettingGatedSource(
            settings: SettingsStore(database: database), key: SettingKeys.vocabularyUseContacts,
            source: FakeVocabularySource(["Kim"]))

        #expect(try await source.terms().isEmpty)
        try ConfigEditor(database: database).setSetting(SettingKeys.vocabularyUseContacts, to: .bool(true))
        #expect(try await source.terms().map(\.text) == ["Kim"])
    }
}
