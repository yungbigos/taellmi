import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Opening the tällmi window")
struct OpeningExploreTests {
    private func entry(_ id: String, _ text: String, minutesAgo: Double) -> Entry {
        Entry(
            id: id, createdAt: sampleDate.addingTimeInterval(-minutesAgo * 60), durationSeconds: nil, source: .typed,
            folder: "entries/\(id)", text: text)
    }

    private func library() -> FakeLibrary {
        FakeLibrary(entries: [
            entry("a", "Die Heizung gluckert schon wieder.", minutesAgo: 1),
            entry("b", "Mit Kim im Englischen Garten.", minutesAgo: 60),
        ])
    }

    @Test(
        "the thoughts are loaded before the window shows, in every view that lists thoughts",
        arguments: [ExploreViewKind.stack, .flow, .time])
    func loadedOnOpen(view: ExploreViewKind) async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: view)
        await model.open(selecting: nil)
        #expect(model.entries.map(\.id) == ["a", "b"])
    }

    @Test("space opens with its concepts loaded")
    func spaceLoadsConcepts() async {
        let library = library()
        await library.setConcepts([ConceptSummary(id: "c", kind: "person", name: "Kim", thoughtCount: 1)])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .space)
        await model.open(selecting: nil)
        #expect(model.concepts.map(\.name) == ["Kim"])
    }

    @Test("a thought chosen in the menu bar opens selected, and flow scrolls to it")
    func opensChosenThought() async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: .flow)
        await model.open(selecting: "b")
        #expect(model.detail?.entry.id == "b")
        #expect(model.scrollTarget == "b")
    }

    @Test("after opening in flow, a new thought shows up without switching views")
    func observesAfterOpen() async throws {
        let library = library()
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .flow)
        await model.open(selecting: nil)
        _ = try await library.createThought(text: "Neuer Gedanke.")
        for _ in 0..<100 where model.entries.count < 3 { await Task.yield() }
        #expect(model.entries.count == 3)
    }

    @Test("a clicked thought is selected at once, before it has loaded, so the row never flickers back")
    func choosesAtOnce() async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: .stack)
        await model.open(selecting: nil)
        model.choose("b")
        #expect(model.selectedID == "b")
        for _ in 0..<100 where model.detail?.entry.id != "b" { await Task.yield() }
        #expect(model.detail?.entry.id == "b")
        #expect(model.selectedID == "b")
    }

    @Test("opening twice keeps a single observation and the same thoughts")
    func openTwice() async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: .flow)
        await model.open(selecting: nil)
        await model.open(selecting: "a")
        #expect(model.entries.map(\.id) == ["a", "b"])
        #expect(model.detail?.entry.id == "a")
    }
}

@Suite("Moving through the list with the arrow keys")
struct ListKeyboardTests {
    @Test("↓ and ↑ move to the next and previous thought and stop at the ends")
    func arrows() async {
        let entries = ["a", "b", "c"].enumerated().map { index, id in
            Entry(
                id: id, createdAt: sampleDate.addingTimeInterval(-Double(index) * 60), durationSeconds: nil,
                source: .typed, folder: id, text: "Gedanke \(id)")
        }
        let model = ExploreViewModel(library: FakeLibrary(entries: entries), autosaveDelay: .zero, startView: .stack)
        await model.open(selecting: nil)
        #expect(model.selectedID == "a")
        model.moveSelection(by: 1)
        #expect(model.selectedID == "b")
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        #expect(model.selectedID == "c")
        model.moveSelection(by: -1)
        #expect(model.selectedID == "b")
    }
}

@Suite("stack always shows a thought")
struct StackAutoSelectTests {
    private func library() -> FakeLibrary {
        FakeLibrary(
            entries: ["a", "b"].enumerated().map { index, id in
                Entry(
                    id: id, createdAt: sampleDate.addingTimeInterval(-Double(index) * 60), durationSeconds: nil,
                    source: .typed, folder: id, text: "Gedanke \(id)")
            })
    }

    @Test("opening in stack with nothing chosen opens the newest thought")
    func opensNewest() async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: .stack)
        await model.open(selecting: nil)
        #expect(model.selectedID == "a")
        #expect(model.detail?.entry.id == "a")
    }

    @Test("switching to stack with nothing open opens the newest thought; a chosen one stays")
    func onSwitch() async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: .flow)
        await model.open(selecting: nil)
        #expect(model.detail == nil)
        await model.perform(.showStack)
        #expect(model.detail?.entry.id == "a")

        await model.select("b")
        await model.perform(.showFlow)
        await model.perform(.showStack)
        #expect(model.detail?.entry.id == "b")
    }

    @Test("a chosen thought from outside wins over the newest")
    func explicitWins() async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: .stack)
        await model.open(selecting: "b")
        #expect(model.detail?.entry.id == "b")
    }
}
