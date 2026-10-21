import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Picking a search result goes to it in the view you're in")
struct GoToSearchHitTests {
    private func entry(_ id: String, _ text: String, daysAgo: Double) -> Entry {
        Entry(
            id: id, createdAt: sampleDate.addingTimeInterval(-daysAgo * 86_400), durationSeconds: nil, source: .typed,
            folder: id, text: text)
    }

    private func setUp(_ view: ExploreViewKind) async -> (ExploreViewModel, FakeLibrary, SearchHit) {
        let old = entry("old", "Die Heizung gluckert.", daysAgo: 40)
        let library = FakeLibrary(entries: [entry("new", "Heute an der Isar.", daysAgo: 0), old])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: view)
        await model.open(selecting: nil)
        return (model, library, SearchHit(entry: old, match: .words, wordRanges: [4..<11]))
    }

    @Test("flow scrolls to the thought, and its search words stay marked")
    func flow() async {
        let (model, _, hit) = await setUp(.flow)
        await model.open(hit, searchedFor: "heizung")
        #expect(model.view == .flow)
        #expect(model.scrollTarget == "old")
        #expect(
            model.highlights(in: hit.entry.text, entryID: "old").contains(TextHighlight(range: 4..<11, kind: .word)))
    }

    @Test("flow drops a time filter that hides the thought")
    func flowFilter() async {
        let (model, _, hit) = await setUp(.flow)
        model.query.period = .today
        await model.refresh()
        await model.open(hit, searchedFor: "heizung")
        #expect(model.query.period == .all)
        #expect(model.flowEntries.contains { $0.id == "old" })
    }

    @Test("stack opens the thought's folder, then the thought, and scrolls to it")
    func stack() async throws {
        let (model, library, hit) = await setUp(.stack)
        let folder = try await library.createFolder(named: "Wohnung")
        try await library.file("old", in: folder.id)
        await model.chooseGroup(.loose)
        await model.open(hit, searchedFor: "heizung")
        #expect(model.stackGroup == .folder(folder.id))
        #expect(model.detail?.entry.id == "old")
        #expect(model.scrollTarget == "old")
    }

    @Test("time moves to the thought's day and opens it")
    func time() async {
        let (model, _, hit) = await setUp(.time)
        await model.open(hit, searchedFor: "heizung")
        #expect(model.timeRange.start <= hit.entry.createdAt && hit.entry.createdAt < model.timeRange.end)
        #expect(model.detail?.entry.id == "old")
    }

    @Test("space opens the thought's first concept; with none, it goes to flow")
    func space() async {
        let (model, library, hit) = await setUp(.space)
        let heizung = ConceptSummary(id: "concept:topic:heizung", kind: "topic", name: "Heizung", thoughtCount: 1)
        await library.setConcepts(
            [heizung], details: [ConceptDetail(concept: heizung, thoughts: [hit.entry], appearingWith: [])])
        await library.setMeaning(
            ThoughtMeaning(
                summary: nil, summaryIsEdited: false,
                concepts: [ThoughtConcept(id: heizung.id, kind: "topic", name: "Heizung", utf16Ranges: [4..<11])],
                related: []),
            for: "old")
        await model.open(hit, searchedFor: "heizung")
        #expect(model.view == .space)
        #expect(model.conceptDetail?.concept.id == heizung.id)

        let (other, _, plain) = await setUp(.space)
        await other.open(plain, searchedFor: "heizung")
        #expect(other.view == .flow)
        #expect(other.scrollTarget == "old")
    }
}
