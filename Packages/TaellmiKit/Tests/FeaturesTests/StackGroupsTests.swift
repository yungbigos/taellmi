import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("stack sorted by your folders and by concept")
struct StackGroupsTests {
    private func entry(_ id: String, _ text: String, minutesAgo: Double) -> Entry {
        Entry(
            id: id, createdAt: sampleDate.addingTimeInterval(-minutesAgo * 60), durationSeconds: nil, source: .typed,
            folder: id, text: text)
    }

    /// Waits until the window caught up with an Archive change (it also refreshes from the change notice).
    private func settle(_ model: ExploreViewModel, until done: () -> Bool) async {
        for _ in 0..<500 where !done() { await Task.yield() }
    }

    private func setUp() async -> (ExploreViewModel, FakeLibrary) {
        let library = FakeLibrary(entries: [
            entry("a", "Der Plan für den Umzug steht.", minutesAgo: 1),
            entry("b", "Mit Sam über Weihnachten geredet.", minutesAgo: 10),
            entry("c", "Die Heizung gluckert.", minutesAgo: 20),
        ])
        let sam = ConceptSummary(id: "concept:person:sam", kind: "person", name: "Sam", thoughtCount: 1)
        await library.setConcepts(
            [sam], details: [ConceptDetail(concept: sam, thoughts: [], appearingWith: [])],
            mentions: ["concept:person:sam": ["b"]])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .stack)
        await model.open(selecting: nil)
        return (model, library)
    }

    @Test("with no folders yet, stack shows every thought as loose, newest first")
    func allLoose() async {
        let (model, _) = await setUp()
        #expect(model.stackGroup == .loose)
        #expect(model.entries.map(\.id) == ["a", "b", "c"])
        #expect(model.stackIndex.looseCount == 3)
    }

    @Test("a new folder opens; filing a thought moves it out of the loose ones and into the folder")
    func folders() async throws {
        let (model, _) = await setUp()
        await model.createFolder(named: "Umzug")
        let umzug = try #require(model.stackIndex.folders.first)
        #expect(model.stackGroup == .folder(umzug.folder.id))
        await model.file("a", in: umzug.folder.id)
        await settle(model) { model.entries.map(\.id) == ["a"] }
        #expect(model.entries.map(\.id) == ["a"])
        #expect(model.stackIndex.folders.first?.count == 1)
        await model.chooseGroup(.loose)
        await settle(model) { model.entries.map(\.id) == ["b", "c"] }
        #expect(model.entries.map(\.id) == ["b", "c"])
    }

    @Test("a concept shows the thoughts that mention it, and the first one opens")
    func concept() async {
        let (model, _) = await setUp()
        await model.chooseGroup(.concept("concept:person:sam"))
        #expect(model.entries.map(\.id) == ["b"])
        #expect(model.detail?.entry.id == "b")
    }

    @Test("deleting the open folder goes back to the loose thoughts, which now include its thoughts")
    func deleteFolder() async throws {
        let (model, _) = await setUp()
        await model.createFolder(named: "Umzug")
        let umzug = try #require(model.stackIndex.folders.first)
        await model.file("a", in: umzug.folder.id)
        await model.deleteFolder(umzug.folder.id)
        await settle(model) { model.entries.count == 3 }
        #expect(model.stackGroup == .loose)
        #expect(model.entries.map(\.id) == ["a", "b", "c"])
    }

    @Test("a search narrows the chosen group")
    func searchWithinGroup() async {
        let (model, _) = await setUp()
        model.query.text = "heizung"
        await model.refresh()
        #expect(model.entries.map(\.id) == ["c"])
    }

    @Test("deleting a thought from its menu moves it to trash and opens the next newest; undo brings it back")
    func deleteFromMenu() async {
        let (model, _) = await setUp()
        #expect(model.detail?.entry.id == "a")
        await model.trash("a")
        await settle(model) { model.entries.count == 2 }
        #expect(model.entries.map(\.id) == ["b", "c"])
        #expect(model.detail?.entry.id == "b")
        await model.undoTrash()
        await settle(model) { model.entries.count == 3 }
        #expect(model.entries.map(\.id) == ["a", "b", "c"])
    }
}
