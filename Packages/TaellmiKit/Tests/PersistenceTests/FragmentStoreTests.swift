import Domain
import GRDB
import Persistence
import TestSupport
import Testing

@Suite("Fragments in the graph")
struct FragmentStoreTests {
    struct Harness {
        let database: AppDatabase
        let index: EntryIndex
        let fragments: FragmentStore
        let vectors: VectorStore

        init() throws {
            database = try makeSeededDatabase()
            index = EntryIndex(database: database)
            fragments = FragmentStore(database: database)
            vectors = VectorStore(database: database)
        }

        func addEntry(id: String = "e1", text: String) throws {
            try index.upsert(
                Entry(
                    id: id, createdAt: sampleDate, durationSeconds: nil, source: .typed, folder: "x/\(id)", text: text),
                transcript: nil)
        }

        func spans(_ texts: [String]) -> [TextSpan] {
            var offset = 0
            return texts.map { text in
                defer { offset += text.utf16.count + 1 }
                return TextSpan(text: text, utf16Range: offset..<(offset + text.utf16.count))
            }
        }
    }

    @Test("stored passages belong to their Entry, in order, with their positions")
    func storesInOrder() throws {
        let harness = try Harness()
        try harness.addEntry(text: "Erster Satz. Zweiter Satz.")
        try harness.fragments.replace(
            entryID: "e1", spans: harness.spans(["Erster Satz.", "Zweiter Satz."]), sourceText: "f1",
            method: "test@1")
        let stored = try harness.fragments.fragments(entryID: "e1")
        #expect(stored.map(\.text) == ["Erster Satz.", "Zweiter Satz."])
        #expect(stored.map(\.ordinal) == [0, 1])
        #expect(stored.map(\.utf16Range) == [0..<12, 13..<26])
        let contained = try harness.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM edge WHERE kind = 'contains' AND from_id = 'e1'")
        }
        #expect(contained == 2)
    }

    @Test("re-splitting keeps unchanged passages with their vectors and removes the others")
    func keepsUnchanged() throws {
        let harness = try Harness()
        try harness.addEntry(text: "A. B.")
        let first = try harness.fragments.replace(
            entryID: "e1", spans: harness.spans(["Bleibt gleich.", "Fällt weg."]), sourceText: "f1",
            method: "test@1")
        try harness.vectors.upsert(first.map { ($0.id, [1, 0, 0]) }, space: "m")

        let second = try harness.fragments.replace(
            entryID: "e1", spans: harness.spans(["Bleibt gleich.", "Ganz neu."]), sourceText: "f2", method: "test@1")
        #expect(second[0].id == first[0].id)
        #expect(second[1].id != first[1].id)
        #expect(try harness.vectors.nodeIDs(space: "m") == [first[0].id])
    }

    @Test("the same sentence twice in one Entry gives two distinct passages")
    func duplicateText() throws {
        let harness = try Harness()
        try harness.addEntry(text: "Ja. Ja.")
        let stored = try harness.fragments.replace(
            entryID: "e1", spans: harness.spans(["Ja.", "Ja."]), sourceText: "f1", method: "test@1")
        #expect(Set(stored.map(\.id)).count == 2)
    }

    @Test("an Entry is stale until its passages match its current Text")
    func staleness() throws {
        let harness = try Harness()
        try harness.addEntry(id: "new", text: "Noch nicht aufgeteilt.")
        try harness.addEntry(id: "done", text: "Schon aufgeteilt.")
        try harness.addEntry(id: "waiting", text: "")
        try harness.fragments.replace(
            entryID: "done", spans: harness.spans(["Schon aufgeteilt."]), sourceText: "Schon aufgeteilt.",
            method: "test@1")
        #expect(try harness.fragments.staleEntryIDs(method: "test@1") == ["new"])
    }

    @Test("an Entry whose Text was cleared is stale until its passages are removed")
    func clearedText() throws {
        let harness = try Harness()
        try harness.addEntry(text: "Etwas.")
        try harness.fragments.replace(
            entryID: "e1", spans: harness.spans(["Etwas."]), sourceText: "Etwas.", method: "test@1")
        try harness.addEntry(text: "")
        #expect(try harness.fragments.staleEntryIDs(method: "test@1") == ["e1"])
        try harness.fragments.replace(entryID: "e1", spans: [], sourceText: "", method: "test@1")
        #expect(try harness.fragments.staleEntryIDs(method: "test@1").isEmpty)
        #expect(try harness.fragments.fragments(entryID: "e1").isEmpty)
    }

    @Test("removing an Entry from the index removes its passages")
    func cascadesWithEntry() throws {
        let harness = try Harness()
        try harness.addEntry(text: "Weg damit.")
        try harness.fragments.replace(
            entryID: "e1", spans: harness.spans(["Weg damit."]), sourceText: "f", method: "test@1")
        try harness.index.remove(id: "e1")
        let nodes = try harness.database.reader.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM node") }
        #expect(nodes == 0)
    }

    @Test("passages without a vector from a model are listed per Entry")
    func missingVectors() throws {
        let harness = try Harness()
        try harness.addEntry(text: "Eins. Zwei.")
        let stored = try harness.fragments.replace(
            entryID: "e1", spans: harness.spans(["Eins.", "Zwei."]), sourceText: "f", method: "test@1")
        try harness.vectors.upsert([(stored[0].id, [1, 0, 0])], space: "m")
        #expect(try harness.fragments.entryIDsWithFragmentsMissingVectors(space: "m") == ["e1"])
        try harness.vectors.upsert([(stored[1].id, [0, 1, 0])], space: "m")
        #expect(try harness.fragments.entryIDsWithFragmentsMissingVectors(space: "m").isEmpty)
    }

    @Test("an Entry split by another method is stale")
    func otherMethod() throws {
        let harness = try Harness()
        try harness.addEntry(text: "Etwas.")
        try harness.fragments.replace(
            entryID: "e1", spans: harness.spans(["Etwas."]), sourceText: "Etwas.", method: "old@1")
        #expect(try harness.fragments.staleEntryIDs(method: "new@1") == ["e1"])
    }
}
