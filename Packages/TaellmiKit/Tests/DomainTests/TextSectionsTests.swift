import Domain
import Testing

@Suite("Marking what a search found as one section, never single words")
struct TextSectionsTests {
    private func marked(_ query: String, in text: String) -> [String] {
        let units = Array(text.utf16)
        let words = query.lowercased().split(separator: " ").map(String.init)
        return TextMatch.sections(for: words, in: text).map { String(decoding: units[$0], as: UTF16.self) }
    }

    @Test("a phrase that appears as typed is marked as a whole, every time it appears")
    func phrase() {
        let text = "I read the Book of Life. Later: the book  of life again; of course."
        #expect(marked("book of life", in: text) == ["Book of Life", "book  of life"])
    }

    @Test("words that are spread out mark the sentence that holds them all, not each word")
    func sentence() {
        let text = "Heute war es ruhig. Das Leben steht in diesem Buch, sagt sie. Ende."
        #expect(marked("buch leben", in: text) == ["Das Leben steht in diesem Buch, sagt sie."])
    }

    @Test("a single word is marked where it appears, also inside compounds")
    func single() {
        #expect(marked("vermieter", in: "Der Vermieter und die Vermieterin.") == ["Vermieter", "Vermieter"])
    }

    @Test("no sentence holds every word: nothing is marked rather than loose single words")
    func noneTogether() {
        #expect(marked("buch leben", in: "Ein Buch. Ein Leben.").isEmpty)
    }

    @Test("sentences end at line breaks too")
    func lines() {
        let text = "Liste:\nBuch über das Leben kaufen\nMilch"
        #expect(marked("buch leben", in: text) == ["Buch über das Leben kaufen"])
    }
}
