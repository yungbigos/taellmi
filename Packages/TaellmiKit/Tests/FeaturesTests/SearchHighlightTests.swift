import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Highlighting what search found")
struct SearchHighlightTests {
    private func entry(_ id: String, _ text: String, minutesAgo: Double) -> Entry {
        Entry(
            id: id, createdAt: sampleDate.addingTimeInterval(-minutesAgo * 60), durationSeconds: nil, source: .voice,
            folder: "entries/\(id)", text: text)
    }

    private func makeModel() async -> (ExploreViewModel, FakeLibrary) {
        let library = FakeLibrary(entries: [
            entry("heat", "Die Heizung ist kaputt. Im Büro war es warm.", minutesAgo: 1),
            entry("cold", "Einkaufen erledigt. Die Bude ist eiskalt geworden.", minutesAgo: 60),
        ])
        await library.relate("cold", passage: 20..<50)
        return (ExploreViewModel(library: library, autosaveDelay: .seconds(60)), library)
    }

    private func texts(_ highlights: [TextHighlight], in text: String) -> [String] {
        let units = Array(text.utf16)
        return highlights.map { String(decoding: units[$0.range], as: UTF16.self) }
    }

    @Test("the open thought highlights the search words, and they follow your typing")
    func wordsFollowEdits() async {
        let (model, _) = await makeModel()
        model.query.text = "heizung"
        await model.refresh()
        await model.select("heat")
        #expect(texts(model.highlights(in: model.editorText, entryID: "heat"), in: model.editorText) == ["Heizung"])

        model.editorText = "Morgens: " + model.editorText
        let moved = model.highlights(in: model.editorText, entryID: "heat")
        #expect(texts(moved, in: model.editorText) == ["Heizung"])
        #expect(moved.map(\.kind) == [.word])
    }

    @Test("a related thought is marked and its matching passage is shaded, also after an edit before it")
    func relatedPassage() async {
        let (model, _) = await makeModel()
        model.query.text = "heizung"
        await model.refresh()
        #expect(model.entries.map(\.id) == ["heat", "cold"])
        #expect(model.isRelated("cold"))
        #expect(!model.isRelated("heat"))

        await model.select("cold")
        let edited = "Neu. " + model.editorText
        let shaded = model.highlights(in: edited, entryID: "cold").filter { $0.kind == .passage }
        #expect(texts(shaded, in: edited) == ["Die Bude ist eiskalt geworden."])
    }

    @Test("without a search nothing is highlighted")
    func noSearch() async {
        let (model, _) = await makeModel()
        await model.refresh()
        #expect(model.highlights(in: "Die Heizung ist kaputt.", entryID: "heat").isEmpty)
        #expect(!model.isRelated("cold"))
    }

    @Test("in flow, ⌘G jumps between word matches only; related thoughts are marked but not jumped to")
    func flowMatches() async {
        let (model, _) = await makeModel()
        await model.perform(.showFlow)
        model.query.text = "heizung"
        await model.refresh()
        #expect(model.flowMatches == ["heat"])
        #expect(model.isRelated("cold"))
        #expect(model.flowEntries.count == 2)
    }

    @Test("a palette row shows a snippet around the match, with the search words marked; related rows say so")
    func paletteSnippets() async {
        let (model, _) = await makeModel()
        let palette = CommandPaletteModel(explore: model)
        await palette.update(query: "heizung")
        let thoughts = palette.results.filter { if case .thought = $0.kind { true } else { false } }
        #expect(thoughts.map(\.isRelated) == [false, true])
        let units = Array((thoughts.first?.title ?? "").utf16)
        #expect(thoughts.first?.highlights.map { String(decoding: units[$0], as: UTF16.self) } == ["Heizung"])
    }

    @Test("a late flow refresh never lands in another view, even with the same search")
    func lateFlowSearchIsDropped() async {
        let library = FakeLibrary(entries: [
            entry("heat", "Die Heizung ist kaputt.", minutesAgo: 1),
            entry("bike", "Fahrrad repariert.", minutesAgo: 30),
        ])
        let model = ExploreViewModel(library: library, autosaveDelay: .seconds(60))
        await model.perform(.showFlow)
        model.query.text = "heizung"
        await library.holdSearches(for: "")
        let early = Task { await model.refresh() }
        await library.waitUntilASearchIsHeld()

        await model.perform(.showStack)
        await library.releaseHeldSearches()
        await early.value

        #expect(model.view == .stack)
        #expect(model.entries.map(\.id) == ["heat"])
    }

    @Test("an older refresh that finishes after a newer one with the same search is dropped")
    func olderRefreshIsDropped() async {
        let (model, library) = await makeModel()
        model.query.text = "heizung"
        await library.holdSearches(for: "heizung")
        let early = Task { await model.refresh() }
        await library.waitUntilASearchIsHeld()
        _ = try? await library.createThought(text: "Heizung schon wieder.")
        await model.refresh()
        await library.releaseHeldSearches()
        await early.value
        #expect(model.entries.count == 3)
    }
}
