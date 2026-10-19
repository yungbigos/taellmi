import Domain
import NaturalLanguage

/// Classifies German words with Apple's on-device NaturalLanguage tagger.
public struct NaturalLanguageClassifier: WordClassifier {
    private static let nameTags: Set<NLTag> = [.personalName, .placeName, .organizationName]

    public init() {}

    public func classify(_ text: String) -> [ClassifiedWord] {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        tagger.setLanguage(.german, range: text.startIndex..<text.endIndex)
        var words: [ClassifiedWord] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation]
        ) { nameTag, range in
            let lexical = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            let isName = nameTag.map(Self.nameTags.contains) ?? false
            words.append(
                ClassifiedWord(
                    range: range, isPersonalName: nameTag == .personalName,
                    isContentWord: isName || lexical == .noun))
            return true
        }
        return words
    }
}
