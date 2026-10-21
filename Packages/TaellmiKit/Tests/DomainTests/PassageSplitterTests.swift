import Domain
import Testing

@Suite("Splitting Text into passages")
struct PassageSplitterTests {
    private let splitter = PassageSplitter(targetLength: 80, maxLength: 140)

    private func texts(_ text: String) -> [String] {
        splitter.passages(in: text).map(\.text)
    }

    @Test("a short thought is one passage, without surrounding whitespace")
    func shortText() {
        #expect(texts("  Heute war ein guter Tag.  \n") == ["Heute war ein guter Tag."])
    }

    @Test("empty or blank Text has no passages", arguments: ["", "   ", "\n\n\t"])
    func blank(_ text: String) {
        #expect(texts(text).isEmpty)
    }

    @Test("a blank line always starts a new passage")
    func paragraphs() {
        #expect(texts("Erster Gedanke.\n\nZweiter Gedanke.") == ["Erster Gedanke.", "Zweiter Gedanke."])
    }

    @Test("a long monologue is split at sentence ends into passages no longer than the maximum")
    func longMonologue() {
        let sentences = [
            "Ich war heute früh im Büro und das Meeting mit Marleen hat ewig gedauert.",
            "Honestly, ich weiß nicht, ob das Projekt so noch Sinn ergibt.",
            "Danach bin ich an der Isar spazieren gegangen, das hat gutgetan.",
            "Morgen muss ich unbedingt die Steuererklärung fertig machen!",
            "Und Mutti anrufen, sie hat Geburtstag.",
        ]
        let passages = texts(sentences.joined(separator: " "))
        #expect(passages.count > 1)
        #expect(passages.allSatisfy { $0.count <= 140 })
        #expect(passages.joined(separator: " ") == sentences.joined(separator: " "))
        for passage in passages {
            #expect(sentences.contains { passage.hasPrefix($0) }, "passage must start at a sentence: \(passage)")
        }
    }

    @Test("a sentence longer than the maximum is cut between words")
    func longSentence() {
        let words = Array(repeating: "Zukunftsangst", count: 30).joined(separator: " ")
        let passages = texts(words)
        #expect(passages.count > 1)
        #expect(passages.allSatisfy { $0.count <= 140 && !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
        #expect(passages.joined(separator: " ") == words)
    }

    @Test("each passage's range points at exactly its words, also after umlauts and emoji")
    func rangesPointAtTheWords() {
        let text = "Grüße an Jürgen 🙂. Straße, Maß und Fuß.\n\nNächster Absatz über Öl."
        let utf16 = Array(text.utf16)
        for passage in splitter.passages(in: text) {
            let slice = String(decoding: utf16[passage.utf16Range], as: UTF16.self)
            #expect(slice == passage.text)
        }
    }

    @Test("a hard cut never splits an emoji or a letter with its accent")
    func cutsBetweenCharacters() {
        for tail in ["🙂🙂🙂", "e\u{301}e\u{301}e\u{301}"] {
            let text = String(repeating: "a", count: 139) + tail + String(repeating: "b", count: 20)
            let passages = texts(text)
            #expect(passages.joined() == text)
            #expect(passages.allSatisfy { !$0.contains("\u{FFFD}") })
        }
    }
}

@Suite("Passages in a formatted Text")
struct FormattedPassageTests {
    private let splitter = PassageSplitter(targetLength: 80, maxLength: 140)

    private func texts(_ text: String) -> [String] {
        splitter.passages(in: text).map(\.text)
    }

    @Test("every list item is a passage of its own, at every level; the line before the list stays with its text")
    func listItems() {
        let text =
            "Heute war viel los. Für morgen drei Dinge:\n1. Steuer abgeben.\n2. Oma anrufen.\n\t- Geschenk kaufen\n3. Milch."
        #expect(
            texts(text) == [
                "Heute war viel los. Für morgen drei Dinge:", "Steuer abgeben.", "Oma anrufen.", "Geschenk kaufen",
                "Milch.",
            ])
    }

    @Test("a heading starts a new passage, together with the text under it")
    func headings() {
        #expect(
            texts("Vorher.\n# Urlaub\nWir waren am See.\n# Arbeit\nViel zu tun.") == [
                "Vorher.", "Urlaub\nWir waren am See.", "Arbeit\nViel zu tun.",
            ])
    }

    @Test("a passage's words leave out the markup, and its range covers those words in the Text")
    func wordsAndRanges() throws {
        let text = "- Der Ver**mieter** kommt morgen."
        let passage = try #require(splitter.passages(in: text).first)
        #expect(passage.text == "Der Vermieter kommt morgen.")
        let slice = String(decoding: Array(text.utf16)[passage.utf16Range], as: UTF16.self)
        #expect(slice == "Der Ver**mieter** kommt morgen.")
    }

    @Test("a long list item is split between its sentences")
    func longItem() {
        let sentence = "Ich muss unbedingt noch die Steuererklärung für das letzte Jahr fertig machen."
        let passages = texts("- " + Array(repeating: sentence, count: 3).joined(separator: " "))
        #expect(passages.count > 1)
        #expect(passages.allSatisfy { $0.hasPrefix("Ich muss") })
    }
}
