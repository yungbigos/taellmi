import Domain
import Testing

@Suite("Renaming, merging and re-kinding concepts by hand")
struct ConceptCurationTests {
    private let marlen = ConceptName(kind: "person", name: "Marlen")
    private let marlin = ConceptName(kind: "person", name: "Marlin")
    private let malin = ConceptName(kind: "person", name: "Malin")

    @Test("a renamed concept's name always lands on the new one, whatever case the model uses")
    func rename() {
        var curation = ConceptCuration()
        curation.rename(marlen, to: "Malin")
        #expect(curation.resolve(ConceptName(kind: "person", name: "marlen")) == malin)
        #expect(curation.resolve(marlin) == marlin)
    }

    @Test("merging several keeps one; a later rename of the target carries the merged names along")
    func mergeThenRename() {
        var curation = ConceptCuration()
        curation.merge([marlen, marlin], into: malin)
        #expect(curation.resolve(marlen) == malin)
        #expect(curation.resolve(marlin) == malin)
        curation.rename(malin, to: "Malin K.")
        #expect(curation.resolve(marlen).name == "Malin K.")
        // Malin itself was renamed, not merged: only the merged names can be split off.
        #expect(
            curation.mergedNames(into: ConceptName(kind: "person", name: "Malin K.")).map(\.name).sorted() == [
                "Marlen", "Marlin",
            ])
    }

    @Test("changing a concept's kind moves it, e.g. Zeit from people to topics")
    func changeKind() {
        var curation = ConceptCuration()
        let zeit = ConceptName(kind: "person", name: "Zeit")
        curation.changeKind(zeit, to: "topic")
        #expect(curation.resolve(zeit) == ConceptName(kind: "topic", name: "Zeit"))
    }

    @Test("splitting a merged name off makes it its own concept again")
    func split() {
        var curation = ConceptCuration()
        curation.merge([marlen, marlin], into: malin)
        curation.split(marlin)
        #expect(curation.resolve(marlin) == marlin)
        #expect(curation.resolve(marlen) == malin)
    }

    @Test("merging a concept into itself, or in a circle, never loops")
    func noLoops() {
        var curation = ConceptCuration()
        curation.merge([marlen], into: marlin)
        curation.merge([marlin], into: marlen)
        #expect(curation.resolve(marlen) == marlen)
        #expect(curation.resolve(marlin) == marlen)
        curation.merge([malin], into: malin)
        #expect(curation.resolve(malin) == malin)
    }

    @Test("it round-trips through JSON, as stored in curation.json")
    func roundTrip() throws {
        var curation = ConceptCuration()
        curation.merge([marlen, marlin], into: malin)
        curation.dismissSuggestion([marlen, ConceptName(kind: "person", name: "Martin")])
        #expect(ConceptCuration(json: curation.json) == curation)
    }

    @Test("a rename that only changes the capitals shows the new spelling")
    func spellingOnly() {
        var curation = ConceptCuration()
        curation.rename(malin, to: "malin")
        #expect(curation.resolve(malin).name == "malin")
    }

    @Test("a plain rename is not offered to split off; merged names are")
    func renameIsNotAMerge() {
        var curation = ConceptCuration()
        curation.rename(marlen, to: "Malin")
        #expect(curation.mergedNames(into: malin).isEmpty)
        curation.merge([marlin], into: malin)
        #expect(curation.mergedNames(into: malin).map(\.name) == ["Marlin"])
    }

    @Test("merging into a concept keeps that concept's own spelling")
    func mergeKeepsTargetSpelling() {
        var curation = ConceptCuration()
        curation.rename(malin, to: "MALIN")
        curation.merge([marlen], into: malin)
        #expect(curation.resolve(marlen).name == "MALIN")
    }
}
