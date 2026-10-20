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
            entry("b", "Mit Marleen im Englischen Garten.", minutesAgo: 60),
        ])
    }

    @Test("the thoughts are loaded before the window shows, in every view", arguments: ExploreViewKind.allCases)
    func loadedOnOpen(view: ExploreViewKind) async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: view)
        await model.open(selecting: nil)
        #expect(model.entries.map(\.id) == ["a", "b"])
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

    @Test("opening twice keeps a single observation and the same thoughts")
    func openTwice() async {
        let model = ExploreViewModel(library: library(), autosaveDelay: .zero, startView: .flow)
        await model.open(selecting: nil)
        await model.open(selecting: "a")
        #expect(model.entries.map(\.id) == ["a", "b"])
        #expect(model.detail?.entry.id == "a")
    }
}
