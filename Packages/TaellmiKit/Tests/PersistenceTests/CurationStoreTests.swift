import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Curation file in the Archive")
struct CurationStoreTests {
    @Test("an Archive without curation.json has an empty Vocabulary")
    func emptyByDefault() throws {
        let store = CurationStore(storage: PlainFolderStorage(root: try TemporaryDirectory().url))
        #expect(try store.vocabulary().isEmpty)
    }

    @Test("added terms are saved to curation.json, trimmed, without duplicates, sorted")
    func addTerms() throws {
        let temp = try TemporaryDirectory()
        let store = CurationStore(storage: PlainFolderStorage(root: temp.url))
        try store.addToVocabulary("Kim")
        try store.addToVocabulary("  Kai ")
        try store.addToVocabulary("Kim")

        let reloaded = CurationStore(storage: PlainFolderStorage(root: temp.url))
        #expect(try reloaded.vocabulary().map(\.text) == ["Kai", "Kim"])
        #expect(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("curation.json").path))
    }

    @Test("blank terms are rejected")
    func rejectsBlank() throws {
        let store = CurationStore(storage: PlainFolderStorage(root: try TemporaryDirectory().url))
        #expect(throws: CurationStore.Error.blankTerm) { try store.addToVocabulary("   ") }
    }

    @Test("removing a term keeps the others")
    func removeTerm() throws {
        let store = CurationStore(storage: PlainFolderStorage(root: try TemporaryDirectory().url))
        try store.addToVocabulary("Kim")
        try store.addToVocabulary("Kai")
        try store.removeFromVocabulary("Kim")
        #expect(try store.vocabulary().map(\.text) == ["Kai"])
    }

    @Test("other Curation in the file (added by later versions) survives a Vocabulary change")
    func keepsOtherKeys() throws {
        let temp = try TemporaryDirectory()
        let storage = PlainFolderStorage(root: temp.url)
        try storage.write(Data(#"{"links": [{"from": "a", "to": "b"}], "vocabulary": []}"#.utf8), to: "curation.json")
        try CurationStore(storage: storage).addToVocabulary("Kim")
        let json = try JSONDecoder().decode([String: JSONValue].self, from: storage.read("curation.json"))
        #expect(json["links"] == .array([.object(["from": .string("a"), "to": .string("b")])]))
    }
}
