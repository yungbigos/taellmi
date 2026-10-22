import Domain
import Testing

@Suite("Renaming, merging and re-kinding concepts by hand")
struct ConceptCurationTests {
    private let kym = ConceptName(kind: "person", name: "Kym")
    private let kimm = ConceptName(kind: "person", name: "Kimm")
    private let sam = ConceptName(kind: "person", name: "Sam")

    @Test("a renamed concept's name always lands on the new one, whatever case the model uses")
    func rename() {
        var curation = ConceptCuration()
        curation.rename(kym, to: "Sam")
        #expect(curation.resolve(ConceptName(kind: "person", name: "kym")) == sam)
        #expect(curation.resolve(kimm) == kimm)
    }

    @Test("merging several keeps one; a later rename of the target carries the merged names along")
    func mergeThenRename() {
        var curation = ConceptCuration()
        curation.merge([kym, kimm], into: sam)
        #expect(curation.resolve(kym) == sam)
        #expect(curation.resolve(kimm) == sam)
        curation.rename(sam, to: "Sam K.")
        #expect(curation.resolve(kym).name == "Sam K.")
        // Sam itself was renamed, not merged: only the merged names can be split off.
        #expect(
            curation.mergedNames(into: ConceptName(kind: "person", name: "Sam K.")).map(\.name).sorted() == [
                "Kimm", "Kym",
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
        curation.merge([kym, kimm], into: sam)
        curation.split(kimm)
        #expect(curation.resolve(kimm) == kimm)
        #expect(curation.resolve(kym) == sam)
    }

    @Test("merging a concept into itself, or in a circle, never loops")
    func noLoops() {
        var curation = ConceptCuration()
        curation.merge([kym], into: kimm)
        curation.merge([kimm], into: kym)
        #expect(curation.resolve(kym) == kym)
        #expect(curation.resolve(kimm) == kym)
        curation.merge([sam], into: sam)
        #expect(curation.resolve(sam) == sam)
    }

    @Test("it round-trips through JSON, as stored in curation.json")
    func roundTrip() throws {
        var curation = ConceptCuration()
        curation.merge([kym, kimm], into: sam)
        curation.dismissSuggestion([kym, ConceptName(kind: "person", name: "Martin")])
        #expect(ConceptCuration(json: curation.json) == curation)
    }

    @Test("a rename that only changes the capitals shows the new spelling")
    func spellingOnly() {
        var curation = ConceptCuration()
        curation.rename(sam, to: "sam")
        #expect(curation.resolve(sam).name == "sam")
    }

    @Test("a plain rename is not offered to split off; merged names are")
    func renameIsNotAMerge() {
        var curation = ConceptCuration()
        curation.rename(kym, to: "Sam")
        #expect(curation.mergedNames(into: sam).isEmpty)
        curation.merge([kimm], into: sam)
        #expect(curation.mergedNames(into: sam).map(\.name) == ["Kimm"])
    }

    @Test("merging into a concept keeps that concept's own spelling")
    func mergeKeepsTargetSpelling() {
        var curation = ConceptCuration()
        curation.rename(sam, to: "SAM")
        curation.merge([kym], into: sam)
        #expect(curation.resolve(kym).name == "SAM")
    }
}
