import Domain
import Testing

@Suite("Kölner Phonetik")
struct KoelnerPhonetikTests {
    @Test(
        "matches the reference codes",
        arguments: [
            ("Wikipedia", "3412"),
            ("Müller-Lüdenscheidt", "65752682"),
            ("Kym", "46"),
            ("Kim", "46"),
            ("Christoph", "47823"),
            ("Bein", "16"),
            ("Ben", "16"),
            ("Straße", "8278"),
            ("", ""),
        ])
    func referenceCodes(word: String, code: String) {
        #expect(KoelnerPhonetik.code(word) == code)
    }
}

@Suite("Correcting the Text towards the Vocabulary")
struct VocabularyCorrectorTests {
    /// Classifies words the way the system tagger would, from a fixed table.
    struct FakeClassifier: WordClassifier {
        var names: Set<String> = []
        var functionWords: Set<String> = ["ich", "bin", "kam", "und", "mit", "habe", "mein", "tut", "weh", "heute"]

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
                let word = String(text[start..<index])
                words.append(
                    ClassifiedWord(
                        range: start..<index, isPersonalName: names.contains(word),
                        isContentWord: !functionWords.contains(word.lowercased())))
            }
            return words
        }
    }

    private func corrector(_ terms: [String]) -> VocabularyCorrector {
        VocabularyCorrector(
            terms: terms.map(VocabularyTerm.init(text:)), minSimilarityForNames: 0.6, minSimilarityOtherWords: 0.8)
    }

    @Test("a recognised name that sounds like a Vocabulary term takes its spelling")
    func correctsName() {
        let result = corrector(["Kim"]).correct(
            "Ich habe heute mit Kym telefoniert.", using: FakeClassifier(names: ["Kym"]))
        #expect(result.text == "Ich habe heute mit Kim telefoniert.")
        #expect(result.corrections == [VocabularyCorrection(from: "Kym", to: "Kim")])
    }

    @Test("function words are never touched, even when they sound the same")
    func leavesFunctionWords() {
        let result = corrector(["Ben", "Kim"]).correct("Ich bin müde und kam spät.", using: FakeClassifier())
        #expect(result.text == "Ich bin müde und kam spät.")
        #expect(result.corrections.isEmpty)
    }

    @Test("an ordinary noun is only corrected when it is spelled almost the same")
    func strictForOtherWords() {
        let classifier = FakeClassifier()
        #expect(corrector(["Ben"]).correct("Mein Bein tut weh.", using: classifier).text == "Mein Bein tut weh.")
        #expect(
            corrector(["Jannik"]).correct("Heute Yannik getroffen.", using: classifier).text
                == "Heute Jannik getroffen.")
    }

    @Test("two Vocabulary terms that sound alike make the match ambiguous, so nothing changes")
    func ambiguousTerms() {
        let result = corrector(["Kim", "Kymm"]).correct(
            "Mit Kym gesprochen.", using: FakeClassifier(names: ["Kym"]))
        #expect(result.text == "Mit Kym gesprochen.")
    }

    @Test("an exact match and lower-case words are left alone")
    func exactAndLowercase() {
        let classifier = FakeClassifier(names: ["Kim", "kym"])
        #expect(corrector(["Kim"]).correct("Mit Kim.", using: classifier).corrections.isEmpty)
        #expect(corrector(["Kim"]).correct("die kym", using: classifier).corrections.isEmpty)
    }

    @Test("every occurrence is corrected and recorded, punctuation and English around it survive")
    func multipleOccurrences() {
        let result = corrector(["Kim"]).correct(
            "Kym, honestly. Dann Kym!", using: FakeClassifier(names: ["Kym"]))
        #expect(result.text == "Kim, honestly. Dann Kim!")
        #expect(result.corrections.count == 2)
    }

    @Test("an empty Vocabulary changes nothing")
    func emptyVocabulary() {
        let text = "Ich habe heute mit Kym telefoniert."
        #expect(corrector([]).correct(text, using: FakeClassifier(names: ["Kym"])).text == text)
    }
}
