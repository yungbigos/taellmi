import Foundation

/// A word the app should spell exactly this way, mostly a name.
public struct VocabularyTerm: Sendable, Hashable, Codable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

/// One replacement made in a Text, recorded on the Entry so it stays visible.
public struct VocabularyCorrection: Sendable, Equatable, Codable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// A word in a text, as classified by the system's language tools.
public struct ClassifiedWord: Sendable {
    public var range: Range<String.Index>
    /// The tagger recognised it as a person's name.
    public var isPersonalName: Bool
    /// A noun or name, as opposed to verbs, pronouns, prepositions and other function words.
    public var isContentWord: Bool

    public init(range: Range<String.Index>, isPersonalName: Bool, isContentWord: Bool) {
        self.range = range
        self.isPersonalName = isPersonalName
        self.isContentWord = isContentWord
    }
}

/// Splits a text into classified words. Implemented with Apple's NaturalLanguage framework.
public protocol WordClassifier: Sendable {
    func classify(_ text: String) -> [ClassifiedWord]
}

/// Corrects names in a new Text towards the Vocabulary, using German sound codes plus guards
/// against false corrections ("ich bin" never becomes "ich Ben").
public struct VocabularyCorrector: Sendable {
    public struct Result: Sendable, Equatable {
        public var text: String
        public var corrections: [VocabularyCorrection]
    }

    private let termsByCode: [String: Set<String>]
    private let terms: Set<String>
    private let minSimilarityForNames: Double
    private let minSimilarityOtherWords: Double

    /// - Parameters:
    ///   - minSimilarityForNames: spelling similarity (0…1) needed when the word is recognised as a name.
    ///   - minSimilarityOtherWords: the stricter similarity needed for any other noun.
    public init(terms: [VocabularyTerm], minSimilarityForNames: Double, minSimilarityOtherWords: Double) {
        let words = Set(terms.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) })
        self.terms = words
        termsByCode = Dictionary(grouping: words, by: KoelnerPhonetik.code).mapValues(Set.init)
        self.minSimilarityForNames = minSimilarityForNames
        self.minSimilarityOtherWords = minSimilarityOtherWords
    }

    public func correct(_ text: String, using classifier: any WordClassifier) -> Result {
        guard !terms.isEmpty else { return Result(text: text, corrections: []) }
        var replacements: [(Range<String.Index>, String)] = []
        var corrections: [VocabularyCorrection] = []
        for word in classifier.classify(text) where word.isContentWord || word.isPersonalName {
            let original = String(text[word.range])
            guard let first = original.first, first.isUppercase, !terms.contains(original) else { continue }
            let code = KoelnerPhonetik.code(original)
            guard !code.isEmpty, let candidates = termsByCode[code], candidates.count == 1,
                let term = candidates.first
            else { continue }
            let threshold = word.isPersonalName ? minSimilarityForNames : minSimilarityOtherWords
            guard Self.similarity(original, term) >= threshold else { continue }
            replacements.append((word.range, term))
            corrections.append(VocabularyCorrection(from: original, to: term))
        }
        var corrected = text
        for (range, term) in replacements.reversed() { corrected.replaceSubrange(range, with: term) }
        return Result(text: corrected, corrections: corrections)
    }

    /// 1 − (optimal string alignment distance ÷ longer length), case-insensitive.
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs.lowercased())
        let b = Array(rhs.lowercased())
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        var distance = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { distance[i][0] = i }
        for j in 0...b.count { distance[0][j] = j }
        for i in stride(from: 1, through: a.count, by: 1) {
            for j in stride(from: 1, through: b.count, by: 1) {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                distance[i][j] = min(distance[i - 1][j] + 1, distance[i][j - 1] + 1, distance[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    distance[i][j] = min(distance[i][j], distance[i - 2][j - 2] + 1)
                }
            }
        }
        return 1 - Double(distance[a.count][b.count]) / Double(longest)
    }
}

/// Where Vocabulary terms come from (the user's own list, contacts, later person Concepts).
public protocol VocabularySource: Sendable {
    func terms() async throws -> [VocabularyTerm]
}
