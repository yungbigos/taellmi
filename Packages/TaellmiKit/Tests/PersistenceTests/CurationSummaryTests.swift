import Domain
import Persistence
import TestSupport
import Testing

@Suite("Summaries you edited")
struct CurationSummaryTests {
    @Test("an edited summary is kept in curation.json, next to the vocabulary, and can be removed again")
    func editsSurvive() throws {
        let folder = try TemporaryDirectory()
        let store = CurationStore(storage: PlainFolderStorage(root: folder.url))
        try store.addToVocabulary("Kim")
        try store.setSummary("Mein eigener Satz.", for: "e1")

        let reopened = CurationStore(storage: PlainFolderStorage(root: folder.url))
        #expect(try reopened.summary(for: "e1") == "Mein eigener Satz.")
        #expect(try reopened.vocabulary().map(\.text) == ["Kim"])

        try reopened.setSummary(nil, for: "e1")
        #expect(try reopened.summary(for: "e1") == nil)
    }
}
