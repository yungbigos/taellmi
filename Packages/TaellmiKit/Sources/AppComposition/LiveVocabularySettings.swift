import Config
import Features
import Foundation
import Persistence
import SystemServices

/// Vocabulary settings backed by `curation.json` (the list) and config (the contacts opt-in).
nonisolated struct LiveVocabularySettings: VocabularySettings {
    let curation: CurationStore
    let settings: SettingsStore
    let editor: ConfigEditor

    func terms() async throws -> [String] { try curation.vocabulary().map(\.text) }
    func add(_ term: String) async throws { try curation.addToVocabulary(term) }
    func remove(_ term: String) async throws { try curation.removeFromVocabulary(term) }
    func usesContacts() async throws -> Bool { try settings.bool(SettingKeys.vocabularyUseContacts) }

    func setUsesContacts(_ on: Bool) async throws -> Bool {
        let effective = on ? await ContactsVocabularySource.requestAccess() : false
        try editor.setSetting(SettingKeys.vocabularyUseContacts, to: .bool(effective))
        return effective
    }
}
