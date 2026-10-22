import Domain
import Testing

@Suite("Finding the model's concepts in your own words")
struct ConceptMentionTests {
    private let kinds: Set<String> = ["person", "place", "topic", "emotion"]

    private func answer(_ concepts: [(String, String, String)]) -> JSONValue {
        .object([
            "concepts": .array(
                concepts.map { name, kind, words in
                    .object(["name": .string(name), "kind": .string(kind), "mention": .string(words)])
                })
        ])
    }

    @Test("each concept points to every place its words appear, as UTF-16 positions")
    func locates() {
        let text = "Mit Kim in Giesing. Später rief Kim nochmal an."
        let mentions = ConceptMentions.locate(
            in: text, answer: answer([("Kim", "person", "Kim"), ("Giesing", "place", "Giesing")]), kinds: kinds)
        let kim = mentions.filter { $0.name == "Kim" }
        #expect(kim.map(\.utf16Range) == [4..<7, 32..<35])
        #expect(mentions.contains { $0.kind == "place" && $0.utf16Range == 11..<18 })
    }

    @Test("a concept whose words aren't in the thought is dropped, never invented")
    func dropsInvented() {
        let mentions = ConceptMentions.locate(
            in: "Die Heizung gluckert.", answer: answer([("Einsamkeit", "emotion", "einsam")]), kinds: kinds)
        #expect(mentions.isEmpty)
    }

    @Test("a concept whose name isn't in the thought is dropped: no feeling is inferred from other words")
    func noInferredNames() {
        let mentions = ConceptMentions.locate(
            in: "Ich habe heute geweint.", answer: answer([("traurig", "emotion", "geweint")]), kinds: kinds)
        #expect(mentions.isEmpty)
    }

    @Test("matching ignores case but not word boundaries")
    func wordBoundaries() {
        let text = "Ich bin müde. Am Samstag kommt Sam."
        let mentions = ConceptMentions.locate(
            in: text, answer: answer([("müde", "emotion", "Müde"), ("Sam", "person", "Sam")]), kinds: kinds)
        #expect(mentions.first { $0.kind == "emotion" }?.utf16Range == 8..<12)
        #expect(mentions.filter { $0.kind == "person" }.map(\.utf16Range) == [31..<34])
    }

    @Test("unknown kinds and empty names are dropped; umlauts and emoji keep positions exact")
    func cleans() {
        let text = "😀 Straße nach Köln"
        let mentions = ConceptMentions.locate(
            in: text,
            answer: answer([("Köln", "place", "Köln"), ("x", "mood", "Straße"), ("", "topic", "Straße")]),
            kinds: kinds)
        #expect(mentions.count == 2)
        #expect(mentions.first { $0.kind == "place" }?.utf16Range == 15..<19)
        #expect(mentions.first { $0.kind == "topic" }?.name == "Straße")
    }
}

@Suite("Concepts in a formatted thought")
struct FormattedConceptMentionTests {
    @Test("a concept's words are found through markup, and point at the Text's own characters")
    func throughMarkup() throws {
        let text = "- Der Ver**mieter** kommt"
        let answer = JSONValue.object([
            "concepts": .array([
                .object(["name": .string("Vermieter"), "kind": .string("person"), "mention": .string("Vermieter")])
            ])
        ])
        let mention = try #require(ConceptMentions.locate(in: text, answer: answer, kinds: ["person"]).first)
        #expect(String(decoding: Array(text.utf16)[mention.utf16Range], as: UTF16.self) == "Ver**mieter")
    }
}
