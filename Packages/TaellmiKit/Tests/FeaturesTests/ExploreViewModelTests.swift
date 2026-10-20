import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Exploring the Archive")
struct ExploreViewModelTests {
    private func entry(_ id: String, _ text: String, minutesAgo: Double, source: EntrySource = .voice) -> Entry {
        Entry(
            id: id, createdAt: sampleDate.addingTimeInterval(-minutesAgo * 60), durationSeconds: nil, source: source,
            folder: "entries/\(id)", text: text)
    }

    private func makeModel() -> (ExploreViewModel, FakeLibrary) {
        let library = FakeLibrary(entries: [
            entry("a", "Zukunftsangst wegen dem Job.", minutesAgo: 1),
            entry("b", "Im Büro mit Marleen.", minutesAgo: 60, source: .typed),
        ])
        return (ExploreViewModel(library: library, autosaveDelay: .zero), library)
    }

    @Test("the window opens in the view it is given", arguments: ExploreViewKind.allCases)
    func startsInGivenView(view: ExploreViewKind) {
        let model = ExploreViewModel(library: FakeLibrary(entries: []), autosaveDelay: .zero, startView: view)
        #expect(model.view == view)
    }

    @Test("shows all Entries newest first, and narrows them while you type a search")
    func listAndSearch() async {
        let (model, _) = makeModel()
        await model.refresh()
        #expect(model.entries.map(\.id) == ["a", "b"])
        model.query.text = "büro"
        await model.refresh()
        #expect(model.entries.map(\.id) == ["b"])
    }

    @Test("selecting an Entry opens its Text in the editor")
    func select() async {
        let (model, _) = makeModel()
        await model.refresh()
        await model.select("b")
        #expect(model.detail?.entry.id == "b")
        #expect(model.editorText == "Im Büro mit Marleen.")
    }

    @Test("edits are saved automatically")
    func autosave() async {
        let (model, library) = makeModel()
        await model.refresh()
        await model.select("a")
        model.editorText = "Zukunftsangst wegen dem Job. Heute besser."
        await model.saveIfNeeded()
        #expect(await library.savedTexts["a"] == "Zukunftsangst wegen dem Job. Heute besser.")
    }

    @Test("switching to another Entry saves pending edits of the previous one first")
    func flushOnSwitch() async {
        let (model, library) = makeModel()
        await model.refresh()
        await model.select("a")
        model.editorText = "Geändert."
        await model.select("b")
        #expect(await library.savedTexts["a"] == "Geändert.")
        #expect(model.editorText == "Im Büro mit Marleen.")
    }

    @Test("an unchanged Text is not written again")
    func noNeedlessWrites() async {
        let (model, library) = makeModel()
        await model.refresh()
        await model.select("a")
        await model.saveIfNeeded()
        #expect(await library.savedTexts.isEmpty)
    }

    @Test("deleting moves the Entry to the Trash, and undo brings it back")
    func trashAndUndo() async {
        let (model, _) = makeModel()
        await model.refresh()
        await model.select("a")
        await model.trashSelected()
        #expect(model.entries.map(\.id) == ["b"])
        #expect(model.detail == nil)
        await model.undoTrash()
        #expect(model.entries.map(\.id) == ["a", "b"])
    }

    @Test("the Papierkorb view lists trashed Entries, which can be restored or deleted for good")
    func trashView() async throws {
        let (model, _) = makeModel()
        await model.refresh()
        await model.select("a")
        await model.trashSelected()
        await model.select("b")
        await model.trashSelected()

        model.showsTrash = true
        await model.refresh()
        #expect(model.trashedEntries.map(\.entry.id) == ["a", "b"])

        await model.restore(try #require(model.trashedEntries.first))
        await model.deleteForever(try #require(model.trashedEntries.first))
        #expect(model.trashedEntries.isEmpty)
        model.showsTrash = false
        await model.refresh()
        #expect(model.entries.map(\.id) == ["a"])
    }
}
