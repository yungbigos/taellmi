import Domain
import Persistence
import TestSupport
import Testing

@Suite("Folders you make by hand")
struct CurationFolderTests {
    private func store(_ folder: TemporaryDirectory) -> CurationStore {
        CurationStore(storage: PlainFolderStorage(root: folder.url))
    }

    @Test("a folder is created, kept in curation.json next to the rest, and comes back after reopening")
    func createAndReopen() throws {
        let dir = try TemporaryDirectory()
        try store(dir).addToVocabulary("Malin")
        let umzug = try store(dir).createFolder(named: "Umzug")
        _ = try store(dir).createFolder(named: "Wohnung")
        #expect(try store(dir).folders().map(\.name) == ["Umzug", "Wohnung"])
        #expect(try store(dir).folders().first?.id == umzug.id)
        #expect(try store(dir).vocabulary().map(\.text) == ["Malin"])
    }

    @Test("a blank or duplicate name is refused")
    func refusesBadNames() throws {
        let dir = try TemporaryDirectory()
        _ = try store(dir).createFolder(named: "Umzug")
        #expect(throws: CurationStore.Error.blankName) { try store(dir).createFolder(named: "  ") }
        #expect(throws: CurationStore.Error.duplicateName) { try store(dir).createFolder(named: "umzug") }
    }

    @Test("a thought is filed in one folder at a time, and can be made loose again")
    func filing() throws {
        let dir = try TemporaryDirectory()
        let umzug = try store(dir).createFolder(named: "Umzug")
        let wohnung = try store(dir).createFolder(named: "Wohnung")
        try store(dir).file("e1", in: umzug.id)
        try store(dir).file("e1", in: wohnung.id)
        #expect(try store(dir).filed() == ["e1": wohnung.id])
        try store(dir).file("e1", in: nil)
        #expect(try store(dir).filed().isEmpty)
        #expect(throws: CurationStore.Error.unknownFolder) { try store(dir).file("e1", in: "nope") }
    }

    @Test("renaming keeps the thoughts; deleting a folder makes its thoughts loose, never deletes them")
    func renameAndDelete() throws {
        let dir = try TemporaryDirectory()
        let umzug = try store(dir).createFolder(named: "Umzug")
        try store(dir).file("e1", in: umzug.id)
        try store(dir).renameFolder(umzug.id, to: "Umzug 2027")
        #expect(try store(dir).folders().map(\.name) == ["Umzug 2027"])
        #expect(try store(dir).filed() == ["e1": umzug.id])
        try store(dir).deleteFolder(umzug.id)
        #expect(try store(dir).folders().isEmpty)
        #expect(try store(dir).filed().isEmpty)
    }
}
