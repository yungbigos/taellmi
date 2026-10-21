import Domain
import Foundation
import Testing

/// The words a range points at, to keep expectations readable.
private func slice(_ text: String, _ range: Range<Int>) -> String {
    String(decoding: Array(text.utf16)[range], as: UTF16.self)
}

@Suite("Reading the Formatting of a Text")
struct TextFormattingTests {
    private func spans(_ text: String) -> [(TextFormatting.Span.Style, String)] {
        TextFormatting(text).spans.map { ($0.style, slice(text, $0.content)) }
    }

    @Test(
        "bold, italic, strike-through and underline are read with their words",
        arguments: [
            ("ein **wichtiger** Tag", TextFormatting.Span.Style.bold, "wichtiger"),
            ("ein __wichtiger__ Tag", .bold, "wichtiger"),
            ("ein *leiser* Tag", .italic, "leiser"),
            ("ein _leiser_ Tag", .italic, "leiser"),
            ("ein ~~falscher~~ Tag", .strikethrough, "falscher"),
            ("ein ~falscher~ Tag", .strikethrough, "falscher"),
            ("ein <u>wichtiger</u> Tag", .underline, "wichtiger"),
            ("ein ++wichtiger++ Tag", .underline, "wichtiger"),
        ])
    func inlineStyles(text: String, style: TextFormatting.Span.Style, words: String) throws {
        let found = try #require(spans(text).first)
        #expect(found.0 == style)
        #expect(found.1 == words)
    }

    @Test("the markers around the words are known, so they can be hidden and left out")
    func markers() throws {
        let text = "sehr **wichtig** heute"
        let span = try #require(TextFormatting(text).spans.first)
        #expect(slice(text, span.opening) == "**")
        #expect(slice(text, span.closing) == "**")
        #expect(slice(text, span.full) == "**wichtig**")
    }

    @Test("bold inside a word counts, underscores inside a word don't")
    func insideWords() {
        #expect(spans("Der Ver**mieter** kommt.").map(\.1) == ["mieter"])
        #expect(spans("snake_case_name bleibt").isEmpty)
    }

    @Test(
        "lone or spaced-out markers stay plain text",
        arguments: ["5 * 3 * 2", "a ** b", "**offen", "nur ~ und ~ so", "x++ und ++y", "ein *  * Stern"])
    func plainMarkers(text: String) {
        #expect(TextFormatting(text).spans.isEmpty)
    }

    @Test("styles nest: bold and italic together, italic inside bold")
    func nesting() {
        let both = spans("***laut***")
        #expect(both.contains { $0.0 == .bold && $0.1 == "laut" })
        #expect(both.contains { $0.0 == .italic && $0.1 == "**laut**" })
        #expect(WordsOnlyText("***laut***").words == "laut")
        let inner = spans("**sehr *laut* heute**")
        #expect(inner.contains { $0.0 == .bold && $0.1 == "sehr *laut* heute" })
        #expect(inner.contains { $0.0 == .italic && $0.1 == "laut" })
    }

    @Test("inline code is left as it is")
    func code() {
        #expect(spans("schreib `**nicht fett**` so").isEmpty)
    }

    @Test("a link shows its words; its address is part of the closing markup")
    func link() throws {
        let text = "siehe [die Seite](https://example.org/a) dort"
        let span = try #require(TextFormatting(text).spans.first)
        #expect(span.style == .link(url: "https://example.org/a"))
        #expect(slice(text, span.content) == "die Seite")
        #expect(slice(text, span.closing) == "](https://example.org/a)")
    }

    @Test("an image link from an import is recognised")
    func image() throws {
        let text = "![](Attachments/foto.png)"
        let span = try #require(TextFormatting(text).spans.first)
        #expect(span.style == .image(source: "Attachments/foto.png"))
    }

    @Test("formatting never runs across lines")
    func perLine() {
        #expect(TextFormatting("**anfang\nende**").spans.isEmpty)
    }
}

@Suite("Reading lines: lists, headings, quotes")
struct TextFormattingLineTests {
    private func kinds(_ text: String) -> [TextFormatting.Line.Kind] {
        TextFormatting(text).lines.map(\.kind)
    }

    @Test("bullets, numbers and checklists are list items; the marker is separate from the words")
    func listItems() throws {
        let text = "- Milch\n1. Steuer\n- [ ] Oma\n- [x] Brot\n* Stern\n+ Plus"
        let lines = TextFormatting(text).lines
        #expect(
            lines.map(\.kind) == [
                .listItem(.bullet, level: 0), .listItem(.numbered(1), level: 0),
                .listItem(.checklist(checked: false), level: 0), .listItem(.checklist(checked: true), level: 0),
                .listItem(.bullet, level: 0), .listItem(.bullet, level: 0),
            ])
        #expect(lines.map { slice(text, $0.content) } == ["Milch", "Steuer", "Oma", "Brot", "Stern", "Plus"])
        #expect(slice(text, lines[2].marker) == "- [ ] ")
    }

    @Test("indentation makes levels, whether it is tabs or spaces")
    func levels() {
        #expect(
            kinds("- a\n\t- b\n\t\t- c\n- d") == [
                .listItem(.bullet, level: 0), .listItem(.bullet, level: 1), .listItem(.bullet, level: 2),
                .listItem(.bullet, level: 0),
            ])
        #expect(
            kinds("1. a\n   1. b\n2. c") == [
                .listItem(.numbered(1), level: 0), .listItem(.numbered(1), level: 1),
                .listItem(.numbered(2), level: 0),
            ])
        #expect(kinds("- a\n    - b") == [.listItem(.bullet, level: 0), .listItem(.bullet, level: 1)])
    }

    @Test("a number starts a list only at one, or when it continues one, so dates stay sentences")
    func germanDates() {
        #expect(kinds("3. Oktober war schön.") == [.plain])
        #expect(kinds("2026. war ein Jahr.") == [.plain])
        #expect(kinds("1. eins\n2. zwei") == [.listItem(.numbered(1), level: 0), .listItem(.numbered(2), level: 0)])
    }

    @Test("a blank line between items keeps the list going; a sentence ends it")
    func looseLists() {
        #expect(
            kinds("1. a\n\n2. b\nText\n2. c") == [
                .listItem(.numbered(1), level: 0), .plain, .listItem(.numbered(2), level: 0), .plain, .plain,
            ])
    }

    @Test("headings have levels; a # without a space is not one")
    func headings() {
        #expect(
            kinds("# Titel\n## Teil\n### Unterteil\n#hashtag") == [
                .heading(level: 1), .heading(level: 2), .heading(level: 3), .plain,
            ])
    }

    @Test("quotes, code blocks and plain lines")
    func others() {
        #expect(kinds("> zitiert\n```\n**code**\n```\nnormal") == [.quote, .code, .code, .code, .plain])
        #expect(TextFormatting("```\n**code**\n```").spans.isEmpty)
    }

    @Test("words inside list items and headings are read for bold and the rest")
    func inlineInBlocks() throws {
        let text = "- **wichtig**\n# Ein *Titel*"
        let words = TextFormatting(text).spans.map { slice(text, $0.content) }
        #expect(words == ["wichtig", "Titel"])
    }

    @Test("line ranges cover each line without its line break, also after umlauts and emoji")
    func lineRanges() {
        let text = "Grüße 🙂\n- Öl\n"
        #expect(TextFormatting(text).lines.map { slice(text, $0.range) } == ["Grüße 🙂", "- Öl", ""])
    }
}

@Suite("The words of a Text, without its Formatting")
struct WordsOnlyTextTests {
    @Test("markup is left out: inline markers, list markers, headings, quotes and link addresses")
    func leavesOutMarkup() {
        let text = "# Titel\n- sehr **wichtig**\n1. Ver**mieter** anrufen\n> [Seite](https://x.org)\n- [ ] Brot"
        #expect(WordsOnlyText(text).words == "Titel\nsehr wichtig\nVermieter anrufen\nSeite\nBrot")
    }

    @Test("a Text without Formatting is its own words")
    func plain() {
        let text = "Heute war ein guter Tag. Grüße 🙂"
        #expect(WordsOnlyText(text).words == text)
    }

    @Test("a range in the words maps back to the same words in the Text")
    func mapsBack() throws {
        let text = "Der Ver**mieter** kommt."
        let view = WordsOnlyText(text)
        let words = view.words as NSString
        let found = words.range(of: "Vermieter")
        let back = view.sourceRange(found.location..<(found.location + found.length))
        #expect(slice(text, back) == "Ver**mieter")
    }

    @Test("a range reaching past the words maps to no more than the Text")
    func clampsToTheText() {
        let view = WordsOnlyText("**ab**")
        #expect(view.sourceRange(0..<99).upperBound <= 6)
        #expect(WordsOnlyText("").sourceRange(0..<3) == 0..<0)
    }

    @Test("a range in the Text maps into the words, dropping the markup")
    func mapsIn() {
        let text = "ein **wichtiger** Tag"
        let view = WordsOnlyText(text)
        let units = Array(view.words.utf16)
        let inWords = view.wordsRange(fromSource: 0..<(text.utf16.count))
        #expect(String(decoding: units[inWords], as: UTF16.self) == "ein wichtiger Tag")
        let bold = view.wordsRange(fromSource: 4..<17)
        #expect(String(decoding: units[bold], as: UTF16.self) == "wichtiger")
    }
}

@Suite("Which markup is hidden while you edit")
struct MarkupVisibilityTests {
    /// The Text as it looks: hidden markup left out.
    private func shown(_ text: String, cursor: Int?) -> String {
        let visibility = TextFormatting(text).visibility(selection: cursor.map { $0..<$0 })
        var units = Array(text.utf16)
        for range in visibility.hidden.sorted(by: { $0.lowerBound > $1.lowerBound }) { units.removeSubrange(range) }
        return String(decoding: units, as: UTF16.self)
    }

    @Test("markup is hidden everywhere except around the formatted words the cursor is in or next to")
    func inlineReveal() {
        let text = "ein **wichtiger** und *leiser* Tag"
        #expect(shown(text, cursor: nil) == "ein wichtiger und leiser Tag")
        #expect(shown(text, cursor: 8) == "ein **wichtiger** und leiser Tag")
        #expect(shown(text, cursor: 17) == "ein **wichtiger** und leiser Tag")
        #expect(shown(text, cursor: 18) == "ein wichtiger und leiser Tag")
    }

    @Test("a bullet's `- ` shows only with the cursor at the start of the item; numbers always show")
    func listMarkers() {
        let text = "- Milch\n1. Steuer"
        #expect(shown(text, cursor: 2) == "- Milch\n1. Steuer")
        #expect(shown(text, cursor: 5) == "Milch\n1. Steuer")
        #expect(TextFormatting(text).visibility(selection: 5..<5).bullets == [0])
        #expect(TextFormatting(text).visibility(selection: 2..<2).bullets.isEmpty)
    }

    @Test("a list item's indentation is always hidden; its level is drawn as an indent instead")
    func indentation() {
        #expect(shown("- a\n\t1. b", cursor: 6) == "a\n1. b")
        #expect(shown("- a\n\t- b", cursor: 7) == "a\n- b")
    }

    @Test("a heading's `#` and a quote's `>` show while the cursor is on that line")
    func lineMarkers() {
        let text = "# Titel\n> zitiert"
        #expect(shown(text, cursor: 4) == "# Titel\nzitiert")
        #expect(shown(text, cursor: 12) == "Titel\n> zitiert")
    }

    @Test("a missing image is hidden behind a placeholder until the cursor touches it")
    func images() {
        let text = "vorher ![](Attachments/a.png) nachher"
        let hidden = TextFormatting(text).visibility(selection: nil)
        #expect(hidden.placeholders == [7])
        #expect(shown(text, cursor: nil) == "vorher ! nachher")
        #expect(TextFormatting(text).visibility(selection: 10..<10).placeholders.isEmpty)
    }

    @Test("code is never hidden")
    func code() {
        #expect(shown("```\n**x**\n```", cursor: nil) == "```\n**x**\n```")
    }
}
