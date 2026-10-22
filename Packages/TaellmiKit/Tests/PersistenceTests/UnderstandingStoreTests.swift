import Domain
import GRDB
import Persistence
import TestSupport
import Testing

@Suite("Concepts and summaries in the graph")
struct UnderstandingStoreTests {
    struct Harness {
        let index: EntryIndex
        let fragments: FragmentStore
        let store: UnderstandingStore

        init() throws {
            let database = try makeSeededDatabase()
            index = EntryIndex(database: database)
            fragments = FragmentStore(database: database)
            store = UnderstandingStore(database: database)
        }

        /// An Entry split into one passage per sentence-line.
        func add(_ id: String, _ lines: [String]) throws {
            let text = lines.joined(separator: "\n")
            try index.upsert(
                Entry(
                    id: id, createdAt: sampleDate, durationSeconds: nil, source: .typed, folder: "x/\(id)", text: text),
                transcript: nil)
            var offset = 0
            let spans = lines.map { line in
                defer { offset += line.utf16.count + 1 }
                return TextSpan(text: line, utf16Range: offset..<(offset + line.utf16.count))
            }
            try fragments.replace(entryID: id, spans: spans, sourceText: text, method: "test@1")
        }

        func understand(_ id: String, summary: String?, _ mentions: [ConceptMention], prompts: String = "p@1") throws {
            let text = try #require(try index.entry(id: id)).text
            _ = try store.replace(
                entryID: id, sourceText: text,
                understanding: Understanding(summary: summary, mentions: mentions),
                provenance: .init(modelID: "apple", promptRefs: prompts))
        }
    }

    private func mention(_ kind: String, _ name: String, _ range: Range<Int>) -> ConceptMention {
        ConceptMention(kind: kind, name: name, utf16Range: range)
    }

    @Test("a thought keeps its summary and its concepts, each linked to the passage and words that name it")
    func storesAndReads() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim telefoniert.", "Die Heizung gluckert."])
        try h.understand(
            "a", summary: "Telefonat mit Kim; die Heizung macht Geräusche.",
            [mention("person", "Kim", 4..<7), mention("topic", "Heizung", 25..<32)])

        let read = try #require(try h.store.understanding(entryID: "a"))
        #expect(read.summary == "Telefonat mit Kim; die Heizung macht Geräusche.")
        #expect(read.concepts.map(\.name) == ["Kim", "Heizung"])
        #expect(read.concepts.first?.utf16Ranges == [4..<7])
    }

    @Test("the same name in two thoughts is one concept; a different kind is another")
    func mergesSameName() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim."])
        try h.add("b", ["Kim kommt morgen."])
        try h.understand("a", summary: nil, [mention("person", "Kim", 4..<7)])
        try h.understand("b", summary: nil, [mention("person", "kim", 0..<3)])

        let concepts = try h.store.concepts()
        #expect(concepts.count == 1)
        #expect(concepts.first?.thoughtCount == 2)
        #expect(try h.store.entryIDs(mentioning: try #require(concepts.first).id).sorted() == ["a", "b"])
    }

    @Test("understanding a thought again replaces its concepts; concepts nobody mentions disappear")
    func replaces() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim in Giesing."])
        try h.understand(
            "a", summary: nil, [mention("person", "Kim", 4..<7), mention("place", "Giesing", 11..<18)])
        try h.understand("a", summary: nil, [mention("place", "Giesing", 11..<18)])

        #expect(try h.store.concepts().map(\.name) == ["Giesing"])
    }

    @Test("concepts list most-mentioned first, and show which concepts appear with them")
    func overview() throws {
        let h = try Harness()
        try h.add("a", ["Kim in Giesing."])
        try h.add("b", ["Kim und Jonas."])
        try h.understand(
            "a", summary: nil, [mention("person", "Kim", 0..<3), mention("place", "Giesing", 7..<14)])
        try h.understand("b", summary: nil, [mention("person", "Kim", 0..<3), mention("person", "Jonas", 8..<13)])

        let concepts = try h.store.concepts()
        #expect(concepts.first?.name == "Kim")
        let kim = try #require(concepts.first)
        #expect(Set(try h.store.appearingWith(kim.id).map(\.name)) == ["Giesing", "Jonas"])
    }

    @Test("a thought is stale until understood, and again when its text or the prompts change")
    func staleness() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim."])
        #expect(try h.store.staleEntryIDs(promptRefs: "p@1") == ["a"])
        try h.understand("a", summary: nil, [])
        #expect(try h.store.staleEntryIDs(promptRefs: "p@1").isEmpty)
        #expect(try h.store.staleEntryIDs(promptRefs: "p@2") == ["a"])
        try h.add("a", ["Mit Kim und Jonas."])
        #expect(try h.store.staleEntryIDs(promptRefs: "p@1") == ["a"])
    }

    @Test("splitting a thought into passages differently makes it stale, so its concepts come back")
    func resplit() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim."])
        try h.understand("a", summary: nil, [mention("person", "Kim", 4..<7)])
        try h.fragments.replace(
            entryID: "a", spans: [TextSpan(text: "Mit Kim.", utf16Range: 0..<8)], sourceText: "Mit Kim.",
            method: "test@2")
        #expect(try h.store.staleEntryIDs(promptRefs: "p@1") == ["a"])
    }

    @Test("a thought whose passages aren't split yet waits, instead of being understood without them")
    func waitsForPassages() throws {
        let h = try Harness()
        try h.index.upsert(
            Entry(
                id: "x", createdAt: sampleDate, durationSeconds: nil, source: .typed, folder: "x/x", text: "Neu hier."),
            transcript: nil)
        #expect(try h.store.staleEntryIDs(promptRefs: "p@1").isEmpty)
    }

    @Test("nothing is stored when the Text changed while the model was working")
    func textChangedMeanwhile() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim."])
        try h.add("a", ["Mit Jonas und Kim."])
        let stored = try h.store.replace(
            entryID: "a", sourceText: "Mit Kim.",
            understanding: Understanding(summary: nil, mentions: [mention("person", "Kim", 4..<7)]),
            provenance: .init(modelID: "apple", promptRefs: "p@1"))
        #expect(stored == false)
        #expect(try h.store.understanding(entryID: "a") == nil)
    }

    @Test("an understanding says which Text it was made from, so callers can tell when it no longer fits")
    func sourceText() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim."])
        try h.understand("a", summary: nil, [mention("person", "Kim", 4..<7)])
        #expect(try h.store.understanding(entryID: "a")?.sourceText == "Mit Kim.")
    }

    @Test("concepts nobody mentions any more are pruned after a thought is deleted")
    func pruneAfterDelete() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim."])
        try h.understand("a", summary: nil, [mention("person", "Kim", 4..<7)])
        try h.index.remove(id: "a")
        #expect(try h.store.pruneConcepts() == 1)
    }

    @Test("a deleted thought takes its summary and mentions along")
    func deleteCascades() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kim."])
        try h.understand("a", summary: "Kurz.", [mention("person", "Kim", 4..<7)])
        try h.index.remove(id: "a")
        #expect(try h.store.understanding(entryID: "a") == nil)
        #expect(try h.store.concepts().isEmpty)
    }
}

@Suite("Kinds of concept from config")
struct ConceptKindConfigTests {
    @Test("the seeded kinds come in their configured order, with the words and symbols users see")
    func seeded() throws {
        let kinds = try UnderstandingStore(database: try makeSeededDatabase()).conceptKindDetails()
        #expect(kinds.map(\.plural) == ["people", "places", "topics", "feelings"])
        #expect(kinds.first?.symbol == "person")
    }
}

@Suite("Your renames and merges reach the graph")
struct ConceptCurationGraphTests {
    typealias Harness = UnderstandingStoreTests.Harness

    private func mention(_ kind: String, _ name: String, _ range: Range<Int>) -> ConceptMention {
        ConceptMention(kind: kind, name: name, utf16Range: range)
    }

    @Test("merging moves every mention to the concept that stays, with its words still marked")
    func merge() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kym."])
        try h.add("b", ["Kimm kommt."])
        try h.understand("a", summary: nil, [mention("person", "Kym", 4..<7)])
        try h.understand("b", summary: nil, [mention("person", "Kimm", 0..<4)])
        var curation = ConceptCuration()
        curation.merge(
            [ConceptName(kind: "person", name: "Kym"), ConceptName(kind: "person", name: "Kimm")],
            into: ConceptName(kind: "person", name: "Sam"))
        try h.store.apply(curation)
        let concepts = try h.store.concepts()
        #expect(concepts.map(\.name) == ["Sam"])
        #expect(concepts.first?.thoughtCount == 2)
        #expect(try h.store.understanding(entryID: "a")?.concepts.first?.utf16Ranges == [4..<7])
    }

    @Test("a thought understood again after a merge lands on the merged concept")
    func newAnalysisFollows() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kym."])
        var curation = ConceptCuration()
        curation.rename(ConceptName(kind: "person", name: "Kym"), to: "Sam")
        let text = try #require(try h.index.entry(id: "a")).text
        try h.store.replace(
            entryID: "a", sourceText: text,
            understanding: Understanding(summary: nil, mentions: [mention("person", "Kym", 4..<7)]),
            provenance: .init(modelID: "m", promptRefs: "p"), curation: curation)
        #expect(try h.store.concepts().map(\.name) == ["Sam"])
    }

    @Test("a kind change moves the concept to its new kind")
    func kind() throws {
        let h = try Harness()
        try h.add("a", ["Die Zeit schreibt."])
        try h.understand("a", summary: nil, [mention("person", "Zeit", 4..<8)])
        var curation = ConceptCuration()
        curation.changeKind(ConceptName(kind: "person", name: "Zeit"), to: "topic")
        try h.store.apply(curation)
        #expect(try h.store.concepts().map(\.kind) == ["topic"])
    }

    @Test("splitting a merged name off (or undoing the merge) brings its own concept back in the graph")
    func splitBack() throws {
        let h = try Harness()
        try h.add("a", ["Mit Kym."])
        try h.add("b", ["Sam kommt."])
        try h.understand("a", summary: nil, [mention("person", "Kym", 4..<7)])
        try h.understand("b", summary: nil, [mention("person", "Sam", 0..<3)])
        let kym = ConceptName(kind: "person", name: "Kym")
        var curation = ConceptCuration()
        curation.merge([kym], into: ConceptName(kind: "person", name: "Sam"))
        try h.store.apply(curation)
        #expect(try h.store.concepts().map(\.name) == ["Sam"])
        curation.split(kym)
        try h.store.apply(curation)
        #expect(Set(try h.store.concepts().map(\.name)) == ["Sam", "Kym"])
        #expect(try h.store.understanding(entryID: "a")?.concepts.first?.name == "Kym")
    }

    @Test("a passage naming both merged concepts keeps every word marked once")
    func mergedRangesOnce() throws {
        let h = try Harness()
        try h.add("a", ["Kym, also Sam."])
        try h.understand(
            "a", summary: nil, [mention("person", "Kym", 0..<3), mention("person", "Sam", 10..<13)])
        var curation = ConceptCuration()
        curation.merge([ConceptName(kind: "person", name: "Kym")], into: ConceptName(kind: "person", name: "Sam"))
        try h.store.apply(curation)
        #expect(try h.store.understanding(entryID: "a")?.concepts.first?.utf16Ranges == [0..<3, 10..<13])
    }

    @Test("a spelling-only rename changes the shown name")
    func spellingOnly() throws {
        let h = try Harness()
        try h.add("a", ["Mit Sam."])
        try h.understand("a", summary: nil, [mention("person", "Sam", 4..<7)])
        var curation = ConceptCuration()
        curation.rename(ConceptName(kind: "person", name: "Sam"), to: "SAM")
        try h.store.apply(curation)
        #expect(try h.store.concepts().map(\.name) == ["SAM"])
    }
}
