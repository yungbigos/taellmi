import Domain
import SystemServices
import Testing

@Suite("Word classification with Apple's language tools")
struct NaturalLanguageClassifierTests {
    private func classify(_ text: String) -> [String: ClassifiedWord] {
        let words = NaturalLanguageClassifier().classify(text)
        return Dictionary(words.map { (String(text[$0.range]), $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Test("recognises a German first name in context as a personal name")
    func personalName() throws {
        let words = classify("Ich habe heute mit Marlene telefoniert, und mein Bein tut weh.")
        #expect(try #require(words["Marlene"]).isPersonalName)
        #expect(try #require(words["Bein"]).isContentWord)
        #expect(try #require(words["Bein"]).isPersonalName == false)
    }

    @Test("verbs, pronouns and prepositions are not content words")
    func functionWords() throws {
        let words = classify("Ich bin gestern mit ihr gekommen.")
        for word in ["Ich", "bin", "mit", "ihr", "gekommen"] {
            #expect(try #require(words[word]).isContentWord == false, "\(word)")
        }
    }
}
