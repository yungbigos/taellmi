import Domain
import Testing

@Suite("Finding search words in a Text")
struct TextMatchTests {
    private func found(_ words: [String], in text: String) -> [String] {
        let units = Array(text.utf16)
        return TextMatch.ranges(of: words, in: text).map { String(decoding: units[$0], as: UTF16.self) }
    }

    @Test("every occurrence is found, ignoring case, in text order")
    func everyOccurrence() {
        #expect(found(["angst"], in: "Angst und noch mal ANGST.") == ["Angst", "ANGST"])
    }

    @Test("a word is found inside a compound, like search finds it")
    func wordParts() {
        #expect(found(["angst"], in: "Heute wieder Zukunftsangst.") == ["angst"])
    }

    @Test("several words are all found; overlapping finds are merged")
    func severalWords() {
        #expect(found(["heiz", "heizung"], in: "Die Heizung ist kalt, kalt.") == ["Heizung"])
        #expect(found(["kalt", "heizung"], in: "Die Heizung ist kalt, kalt.") == ["Heizung", "kalt", "kalt"])
    }

    @Test("positions are exact after umlauts and emoji")
    func positions() {
        let text = "Grüße 🙂 an Jürgen, Jürgen!"
        #expect(found(["jürgen"], in: text) == ["Jürgen", "Jürgen"])
    }

    @Test("no words or no Text give no finds", arguments: [([String](), "Text"), (["x"], "")])
    func nothing(words: [String], text: String) {
        #expect(TextMatch.ranges(of: words, in: text).isEmpty)
    }
}

@Suite("A snippet around a match")
struct SnippetTests {
    @Test("a short Text is its own snippet, without ellipses")
    func shortText() {
        let snippet = Snippet(of: "Kurz und gut.", around: 0..<4, maxLength: 80)
        #expect(snippet.text == "Kurz und gut.")
        #expect(!snippet.cutsStart && !snippet.cutsEnd)
    }

    @Test("a long Text is cut around the match at word boundaries, and the match moves along")
    func longText() {
        let text =
            "Am Anfang war ein langer Tag im Büro mit vielen Meetings, und dann war die Heizung wieder kaputt, "
            + "weshalb ich abends frierend auf dem Sofa saß und über alles Mögliche nachgedacht habe."
        let start =
            Array(text.utf16).count
            - Array(
                "Heizung wieder kaputt, weshalb ich abends frierend auf dem Sofa saß und über alles Mögliche nachgedacht habe."
                    .utf16
            ).count
        let snippet = Snippet(of: text, around: start..<(start + 7), maxLength: 60)
        #expect(snippet.cutsStart && snippet.cutsEnd)
        #expect(snippet.text.count <= 60)
        #expect(!snippet.text.hasPrefix(" ") && !snippet.text.hasSuffix(" "))
        let shifted = snippet.ranges([start..<(start + 7)])
        let units = Array(snippet.text.utf16)
        #expect(shifted.map { String(decoding: units[$0], as: UTF16.self) } == ["Heizung"])
    }

    @Test("without a match the snippet is the start of the Text")
    func noMatch() {
        let snippet = Snippet(of: String(repeating: "Wort ", count: 40), around: nil, maxLength: 30)
        #expect(!snippet.cutsStart && snippet.cutsEnd)
        #expect(snippet.text.hasPrefix("Wort"))
    }

    @Test("matches outside the snippet are left out, partly visible ones are clipped")
    func clipping() {
        let text = "Eins zwei drei vier fünf sechs sieben acht neun zehn elf zwölf"
        let snippet = Snippet(of: text, around: 0..<4, maxLength: 20)
        #expect(snippet.ranges([0..<4, 50..<55]).count == 1)
    }

    @Test("a match position past the end of a Text that got shorter is safe", arguments: [0, 3])
    func focusPastEnd(spaces: Int) {
        let text =
            String(repeating: "x", count: 50) + String(repeating: " ", count: spaces) + "https://example.org/sehr/lang"
        let snippet = Snippet(of: text, around: 500..<520, maxLength: 20)
        #expect(snippet.text.count <= 30)
        #expect(snippet.ranges([500..<520]).isEmpty)
    }

    @Test("a cut never splits an emoji")
    func emojiAtCut() {
        let text = String(repeating: "🙂", count: 40)
        let snippet = Snippet(of: text, around: 20..<22, maxLength: 11)
        #expect(!snippet.text.contains("\u{FFFD}"))
    }
}

@Suite("Search words and snippets read the words, not the Formatting")
struct FormattedMatchTests {
    @Test("a word is found through markup inside it, and highlighted on the Text's own characters")
    func throughMarkup() {
        let text = "Der Ver**mieter** kommt. - <u>Oma</u> anrufen"
        let units = Array(text.utf16)
        let found = TextMatch.ranges(of: ["vermieter", "oma"], in: text).map {
            String(decoding: units[$0], as: UTF16.self)
        }
        #expect(found == ["Ver**mieter", "Oma"])
    }

    @Test("a snippet shows the words without markup, and a match in it points at the right words")
    func snippetWithoutMarkup() {
        let text = "- sehr **wichtig** heute\n- <u>Oma</u> anrufen"
        let match = TextMatch.ranges(of: ["wichtig"], in: text)
        let snippet = Snippet(of: text, around: match.first, maxLength: 90)
        #expect(snippet.text == "sehr wichtig heute\nOma anrufen")
        let units = Array(snippet.text.utf16)
        #expect(snippet.ranges(match).map { String(decoding: units[$0], as: UTF16.self) } == ["wichtig"])
    }
}
