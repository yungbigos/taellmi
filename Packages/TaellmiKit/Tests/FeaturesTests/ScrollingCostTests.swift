import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Scrolling stays cheap")
struct ScrollingCostTests {
    private func setUp(debounce: Duration = .zero) async -> (ExploreViewModel, FakeLibrary) {
        let entries = ["a", "b"].enumerated().map { index, id in
            Entry(
                id: id, createdAt: sampleDate.addingTimeInterval(-Double(index) * 60), durationSeconds: nil,
                source: .typed, folder: id, text: "Gedanke \(id)")
        }
        let library = FakeLibrary(entries: entries)
        let model = ExploreViewModel(
            library: library, autosaveDelay: .zero, startView: .flow, changeDebounce: debounce)
        await model.open(selecting: nil)
        return (model, library)
    }

    @Test("a thought scrolled away and back is not loaded again")
    func keptWhileScrolling() async {
        let (model, library) = await setUp()
        await model.loadMeaning(for: "a")
        model.forgetMeaning(for: "a")
        await model.loadMeaning(for: "a")
        #expect(await library.meaningCalls["a"] == 1)
    }

    @Test("after a change only thoughts on screen load again; the others when they come back")
    func onlyVisibleReload() async {
        let (model, library) = await setUp()
        await model.loadMeaning(for: "a")
        await model.loadMeaning(for: "b")
        model.forgetMeaning(for: "b")
        await model.refresh()
        #expect(await library.meaningCalls["a"] == 2)
        #expect(await library.meaningCalls["b"] == 1)
        await model.loadMeaning(for: "b")
        #expect(await library.meaningCalls["b"] == 2)
    }

    @Test("a burst of Archive changes (e.g. the pipeline at work) refreshes the window once")
    func coalesced() async throws {
        let (model, library) = await setUp(debounce: .milliseconds(80))
        let before = await library.searchCalls
        for index in 0..<10 { await library.setMeaning(.empty, for: "x\(index)") }
        try await Task.sleep(for: .milliseconds(400))
        let refreshes = await library.searchCalls - before
        #expect(refreshes >= 1 && refreshes <= 2)
        _ = model
    }
}
