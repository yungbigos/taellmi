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
        try h.add("a", ["Mit Marleen telefoniert.", "Die Heizung gluckert."])
        try h.understand(
            "a", summary: "Telefonat mit Marleen; die Heizung macht Geräusche.",
            [mention("person", "Marleen", 4..<11), mention("topic", "Heizung", 29..<36)])

        let read = try #require(try h.store.understanding(entryID: "a"))
        #expect(read.summary == "Telefonat mit Marleen; die Heizung macht Geräusche.")
        #expect(read.concepts.map(\.name) == ["Marleen", "Heizung"])
        #expect(read.concepts.first?.utf16Ranges == [4..<11])
    }

    @Test("the same name in two thoughts is one concept; a different kind is another")
    func mergesSameName() throws {
        let h = try Harness()
        try h.add("a", ["Mit Marleen."])
        try h.add("b", ["Marleen kommt morgen."])
        try h.understand("a", summary: nil, [mention("person", "Marleen", 4..<11)])
        try h.understand("b", summary: nil, [mention("person", "marleen", 0..<7)])

        let concepts = try h.store.concepts()
        #expect(concepts.count == 1)
        #expect(concepts.first?.thoughtCount == 2)
        #expect(try h.store.entryIDs(mentioning: try #require(concepts.first).id).sorted() == ["a", "b"])
    }

    @Test("understanding a thought again replaces its concepts; concepts nobody mentions disappear")
    func replaces() throws {
        let h = try Harness()
        try h.add("a", ["Mit Marleen in Giesing."])
        try h.understand(
            "a", summary: nil, [mention("person", "Marleen", 4..<11), mention("place", "Giesing", 15..<22)])
        try h.understand("a", summary: nil, [mention("place", "Giesing", 15..<22)])

        #expect(try h.store.concepts().map(\.name) == ["Giesing"])
    }

    @Test("concepts list most-mentioned first, and show which concepts appear with them")
    func overview() throws {
        let h = try Harness()
        try h.add("a", ["Marleen in Giesing."])
        try h.add("b", ["Marleen und Jonas."])
        try h.understand(
            "a", summary: nil, [mention("person", "Marleen", 0..<7), mention("place", "Giesing", 11..<18)])
        try h.understand("b", summary: nil, [mention("person", "Marleen", 0..<7), mention("person", "Jonas", 12..<17)])

        let concepts = try h.store.concepts()
        #expect(concepts.first?.name == "Marleen")
        let marleen = try #require(concepts.first)
        #expect(Set(try h.store.appearingWith(marleen.id).map(\.name)) == ["Giesing", "Jonas"])
    }

    @Test("a thought is stale until understood, and again when its text or the prompts change")
    func staleness() throws {
        let h = try Harness()
        try h.add("a", ["Mit Marleen."])
        #expect(try h.store.staleEntryIDs(promptRefs: "p@1") == ["a"])
        try h.understand("a", summary: nil, [])
        #expect(try h.store.staleEntryIDs(promptRefs: "p@1").isEmpty)
        #expect(try h.store.staleEntryIDs(promptRefs: "p@2") == ["a"])
        try h.add("a", ["Mit Marleen und Jonas."])
        #expect(try h.store.staleEntryIDs(promptRefs: "p@1") == ["a"])
    }

    @Test("splitting a thought into passages differently makes it stale, so its concepts come back")
    func resplit() throws {
        let h = try Harness()
        try h.add("a", ["Mit Marleen."])
        try h.understand("a", summary: nil, [mention("person", "Marleen", 4..<11)])
        try h.fragments.replace(
            entryID: "a", spans: [TextSpan(text: "Mit Marleen.", utf16Range: 0..<12)], sourceText: "Mit Marleen.",
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
        try h.add("a", ["Mit Marleen."])
        try h.add("a", ["Mit Jonas und Marleen."])
        let stored = try h.store.replace(
            entryID: "a", sourceText: "Mit Marleen.",
            understanding: Understanding(summary: nil, mentions: [mention("person", "Marleen", 4..<11)]),
            provenance: .init(modelID: "apple", promptRefs: "p@1"))
        #expect(stored == false)
        #expect(try h.store.understanding(entryID: "a") == nil)
    }

    @Test("an understanding says which Text it was made from, so callers can tell when it no longer fits")
    func sourceText() throws {
        let h = try Harness()
        try h.add("a", ["Mit Marleen."])
        try h.understand("a", summary: nil, [mention("person", "Marleen", 4..<11)])
        #expect(try h.store.understanding(entryID: "a")?.sourceText == "Mit Marleen.")
    }

    @Test("concepts nobody mentions any more are pruned after a thought is deleted")
    func pruneAfterDelete() throws {
        let h = try Harness()
        try h.add("a", ["Mit Marleen."])
        try h.understand("a", summary: nil, [mention("person", "Marleen", 4..<11)])
        try h.index.remove(id: "a")
        #expect(try h.store.pruneConcepts() == 1)
    }

    @Test("a deleted thought takes its summary and mentions along")
    func deleteCascades() throws {
        let h = try Harness()
        try h.add("a", ["Mit Marleen."])
        try h.understand("a", summary: "Kurz.", [mention("person", "Marleen", 4..<11)])
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
