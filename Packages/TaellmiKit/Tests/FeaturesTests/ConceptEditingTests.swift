import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Renaming and merging concepts in the window")
struct ConceptEditingTests {
    private func person(_ name: String, _ count: Int = 1) -> ConceptSummary {
        ConceptSummary(id: "concept:person:\(name.lowercased())", kind: "person", name: name, thoughtCount: count)
    }

    private func setUp() async -> (ExploreViewModel, FakeLibrary) {
        let library = FakeLibrary(entries: [])
        await library.setConcepts([person("Malin"), person("Marlen"), person("Marlin"), person("Manuela Schwesig")])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .stack)
        await model.open(selecting: nil)
        return (model, library)
    }

    @Test("renaming a person saves it, can add the spelling, and the index shows the new name")
    func rename() async {
        let (model, library) = await setUp()
        await model.renameConcept(person("Marlen"), to: "Malena", spell: true)
        #expect(
            await library.conceptCurationValue.resolve(ConceptName(kind: "person", name: "Marlen")).name == "Malena")
        #expect(await library.spellingsAdded == ["Malena"])
        #expect(model.stackIndex.concepts.contains { $0.name == "Malena" })
    }

    @Test("merging several into one keeps that name and adds up their thoughts")
    func merge() async {
        let (model, library) = await setUp()
        await model.mergeConcepts(
            [person("Marlen"), person("Marlin")], into: ConceptName(kind: "person", name: "Malin"), spell: false)
        let malin = model.stackIndex.concepts.first { $0.name == "Malin" }
        #expect(malin?.thoughtCount == 3)
        #expect(!model.stackIndex.concepts.contains { $0.name == "Marlen" })
        #expect(await library.spellingsAdded.isEmpty)
    }

    @Test("undo brings the concepts back as they were")
    func undo() async {
        let (model, library) = await setUp()
        await model.mergeConcepts([person("Marlen")], into: ConceptName(kind: "person", name: "Malin"), spell: false)
        await model.undoConceptChange()
        #expect(await library.conceptCurationValue == ConceptCuration())
        #expect(model.stackIndex.concepts.contains { $0.name == "Marlen" })
    }

    @Test("a kind can be changed, and a merged name split off again")
    func kindAndSplit() async {
        let (model, library) = await setUp()
        await model.changeKind(person("Manuela Schwesig"), to: "topic")
        #expect(model.stackIndex.concepts.first { $0.name == "Manuela Schwesig" }?.kind == "topic")
        await model.mergeConcepts([person("Marlen")], into: ConceptName(kind: "person", name: "Malin"), spell: false)
        #expect(model.mergedNames(into: person("Malin")).map(\.name) == ["Marlen"])
        await model.split(ConceptName(kind: "person", name: "Marlen"))
        #expect(
            await library.conceptCurationValue.resolve(ConceptName(kind: "person", name: "Marlen")).name == "Marlen")
    }

    @Test("names that sound alike are suggested together, until you dismiss them")
    func suggestions() async {
        let (model, _) = await setUp()
        let group = model.conceptSuggestions.first.map { Set($0.map(\.name)) }
        #expect(group == ["Malin", "Marlen", "Marlin"])
        await model.dismissSuggestion(model.conceptSuggestions[0])
        #expect(model.conceptSuggestions.isEmpty)
    }

    @Test("the open concept follows a merge to the concept that stays")
    func followsOpenConcept() async {
        let (model, _) = await setUp()
        await model.chooseGroup(.concept("concept:person:marlen"))
        await model.mergeConcepts([person("Marlen")], into: ConceptName(kind: "person", name: "Malin"), spell: false)
        #expect(model.stackGroup == .concept("concept:person:malin"))
    }

    @Test("⌘Z undoes the last change, not a dismissed suggestion")
    func undoOrder() async {
        let (model, library) = await setUp()
        await model.renameConcept(person("Marlen"), to: "Malena", spell: false)
        await model.dismissSuggestion(model.conceptSuggestions[0])
        await model.undoConceptChange()
        #expect(
            await library.conceptCurationValue.resolve(ConceptName(kind: "person", name: "Marlen")).name == "Marlen")
    }

    @Test("changes made quickly one after another all count")
    func quickChanges() async {
        let (model, library) = await setUp()
        async let first = model.renameConcept(person("Marlen"), to: "Malena", spell: false)
        async let second = model.changeKind(person("Manuela Schwesig"), to: "topic")
        _ = await (first, second)
        let curation = await library.conceptCurationValue
        #expect(curation.resolve(ConceptName(kind: "person", name: "Marlen")).name == "Malena")
        #expect(curation.resolve(ConceptName(kind: "person", name: "Manuela Schwesig")).kind == "topic")
    }
}
