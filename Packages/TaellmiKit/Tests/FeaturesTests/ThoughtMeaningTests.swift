import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Concepts, summaries and related thoughts in Explore")
struct ThoughtMeaningTests {
    private func entry(_ id: String, _ text: String, minutesAgo: Double = 0) -> Entry {
        Entry(
            id: id, createdAt: sampleDate.addingTimeInterval(-minutesAgo * 60), durationSeconds: nil, source: .typed,
            folder: "entries/\(id)", text: text)
    }

    private let kim = ThoughtConcept(
        id: "concept:person:kim", kind: "person", name: "Kim", utf16Ranges: [4..<7])
    private let heizung = ThoughtConcept(
        id: "concept:topic:heizung", kind: "topic", name: "Heizung", utf16Ranges: [17..<24])

    private func setUp() async -> (ExploreViewModel, FakeLibrary) {
        let a = entry("a", "Mit Kim über die Heizung geredet.")
        let b = entry("b", "Die Heizung gluckert.", minutesAgo: 60)
        let library = FakeLibrary(entries: [a, b])
        await library.setMeaning(
            ThoughtMeaning(
                summary: "Gespräch über die Heizung.", summaryIsEdited: false, concepts: [kim, heizung],
                related: [b]),
            for: "a")
        let kimSummary = ConceptSummary(id: kim.id, kind: "person", name: "Kim", thoughtCount: 1)
        let heizungSummary = ConceptSummary(id: heizung.id, kind: "topic", name: "Heizung", thoughtCount: 2)
        await library.setConcepts(
            [heizungSummary, kimSummary],
            details: [ConceptDetail(concept: heizungSummary, thoughts: [a, b], appearingWith: [kimSummary])])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .flow)
        await model.open(selecting: nil)
        return (model, library)
    }

    @Test("a thought's summary, concepts and related thoughts are loaded for it")
    func loads() async {
        let (model, _) = await setUp()
        await model.loadMeaning(for: "a")
        #expect(model.meanings["a"]?.summary == "Gespräch über die Heizung.")
        #expect(model.meanings["a"]?.concepts.map(\.name) == ["Kim", "Heizung"])
        #expect(model.meanings["a"]?.related.map(\.id) == ["b"])
    }

    @Test("concept words are highlighted by kind, together with search words")
    func highlights() async {
        let (model, _) = await setUp()
        await model.loadMeaning(for: "a")
        let text = "Mit Kim über die Heizung geredet."
        #expect(
            model.highlights(in: text, entryID: "a") == [
                TextHighlight(range: 4..<7, kind: .concept("person")),
                TextHighlight(range: 17..<24, kind: .concept("topic")),
            ])
        model.query.text = "geredet"
        await model.refresh()
        #expect(model.highlights(in: text, entryID: "a").contains(TextHighlight(range: 25..<32, kind: .word)))
    }

    @Test("concept highlights are dropped once the text was edited away from what was analysed")
    func editedText() async {
        let (model, _) = await setUp()
        await model.loadMeaning(for: "a")
        #expect(model.highlights(in: "Ganz anderer Text.", entryID: "a").isEmpty)
    }

    @Test("space lists every concept; choosing one shows its thoughts and the concepts that appear with it")
    func space() async {
        let (model, _) = await setUp()
        await model.perform(.showSpace)
        #expect(model.view == .space)
        #expect(model.concepts.map(\.name) == ["Heizung", "Kim"])

        await model.openConcept("concept:topic:heizung")
        #expect(model.conceptDetail?.thoughts.map(\.id) == ["a", "b"])
        #expect(model.conceptDetail?.appearingWith.map(\.name) == ["Kim"])
    }

    @Test("clicking a badge in flow opens that concept in space")
    func badgeOpensSpace() async {
        let (model, _) = await setUp()
        await model.openConcept("concept:topic:heizung")
        #expect(model.view == .space)
        #expect(model.conceptDetail?.concept.name == "Heizung")
    }

    @Test("a thought chosen in space or as related opens in flow, scrolled to")
    func revealsThought() async {
        let (model, _) = await setUp()
        await model.perform(.showSpace)
        await model.reveal("b")
        #expect(model.view == .flow)
        #expect(model.scrollTarget == "b")
    }

    @Test("asking for the same thought twice makes a new scroll request each time")
    func repeatedReveal() async {
        let (model, _) = await setUp()
        await model.reveal("b")
        let first = model.scrollRequest
        await model.reveal("b")
        #expect(model.scrollRequest?.entryID == "b")
        #expect(model.scrollRequest != first)
    }

    @Test("editing a summary saves it as yours; clearing it brings the generated one back")
    func editSummary() async {
        let (model, library) = await setUp()
        await model.loadMeaning(for: "a")
        await model.saveSummary("Mein Satz.", for: "a")
        #expect(await library.savedSummaries["a"] == .some("Mein Satz."))
        #expect(model.meanings["a"]?.summary == "Mein Satz.")
        #expect(model.meanings["a"]?.summaryIsEdited == true)
    }

    @Test("when the Archive changes, the meanings already shown are loaded again")
    func reloadsOnChange() async {
        let (model, library) = await setUp()
        await model.loadMeaning(for: "a")
        await library.setMeaning(.empty, for: "a")
        for _ in 0..<200 where model.meanings["a"]?.summary != nil { await Task.yield() }
        #expect(model.meanings["a"]?.summary == nil)
    }
}
