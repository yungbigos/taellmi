import Domain
import Testing

@Suite("A summary only says what the thought says")
struct SummaryGroundingTests {
    /// Treats every word as meaningful except a few function words, like a tagger would.
    struct Classifier: WordClassifier {
        let function: Set<String> = [
            "ich", "und", "mit", "die", "der", "den", "das", "über", "weil", "nicht", "habe", "eher", "als",
        ]

        func classify(_ text: String) -> [ClassifiedWord] {
            var words: [ClassifiedWord] = []
            var index = text.startIndex
            while index < text.endIndex {
                guard text[index].isLetter else {
                    index = text.index(after: index)
                    continue
                }
                let start = index
                while index < text.endIndex, text[index].isLetter { index = text.index(after: index) }
                let word = String(text[start..<index]).lowercased()
                words.append(
                    ClassifiedWord(
                        range: start..<index, isPersonalName: false, isContentWord: false,
                        carriesMeaning: !function.contains(word)))
            }
            return words
        }
    }

    private let thought =
        "Die Heizung gluckert seit gestern. Ich bin eher müde als genervt und rufe den Vermieter morgen an."

    @Test("a summary made of the thought's own words, in other forms, is shown")
    func grounded() {
        #expect(
            SummaryGrounding.isGrounded(
                "Heizungen gluckern; morgen rufe ich den Vermieter an.", in: thought, classifier: Classifier(),
                stemLength: 5))
    }

    @Test("a separable verb joined up (\"anrufen\" for \"rufe … an\") is not recognised, so that summary stays hidden")
    func separableVerb() {
        #expect(
            !SummaryGrounding.isGrounded(
                "Morgen den Vermieter anrufen.", in: thought, classifier: Classifier(), stemLength: 5))
    }

    @Test("a summary that adds a reason or a feeling the thought doesn't have is not shown")
    func invented() {
        #expect(
            !SummaryGrounding.isGrounded(
                "Ich bin traurig, weil der Vermieter nicht hilft.", in: thought, classifier: Classifier(),
                stemLength: 5))
    }

    @Test("an empty summary is never shown")
    func empty() {
        #expect(!SummaryGrounding.isGrounded("  ", in: thought, classifier: Classifier(), stemLength: 5))
    }
}
