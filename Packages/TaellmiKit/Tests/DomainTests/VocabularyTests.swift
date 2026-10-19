import Domain
import Testing

@Suite("Kölner Phonetik")
struct KoelnerPhonetikTests {
    @Test(
        "matches the reference codes",
        arguments: [
            ("Wikipedia", "3412"),
            ("Müller-Lüdenscheidt", "65752682"),
            ("Marlene", "6756"),
            ("Marleen", "6756"),
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
        let result = corrector(["Marleen"]).correct(
            "Ich habe heute mit Marlene telefoniert.", using: FakeClassifier(names: ["Marlene"]))
        #expect(result.text == "Ich habe heute mit Marleen telefoniert.")
        #expect(result.corrections == [VocabularyCorrection(from: "Marlene", to: "Marleen")])
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
        let result = corrector(["Marleen", "Marlehn"]).correct(
            "Mit Marlene gesprochen.", using: FakeClassifier(names: ["Marlene"]))
        #expect(result.text == "Mit Marlene gesprochen.")
    }

    @Test("an exact match and lower-case words are left alone")
    func exactAndLowercase() {
        let classifier = FakeClassifier(names: ["Marleen"])
        #expect(corrector(["Marleen"]).correct("Mit Marleen.", using: classifier).corrections.isEmpty)
        #expect(corrector(["Marleen"]).correct("die marlene", using: classifier).corrections.isEmpty)
    }

    @Test("every occurrence is corrected and recorded, punctuation and English around it survive")
    func multipleOccurrences() {
        let result = corrector(["Marleen"]).correct(
            "Marlene, honestly. Dann Marlene!", using: FakeClassifier(names: ["Marlene"]))
        #expect(result.text == "Marleen, honestly. Dann Marleen!")
        #expect(result.corrections.count == 2)
    }

    @Test("an empty Vocabulary changes nothing")
    func emptyVocabulary() {
        let text = "Ich habe heute mit Marlene telefoniert."
        #expect(corrector([]).correct(text, using: FakeClassifier(names: ["Marlene"])).text == text)
    }
}
