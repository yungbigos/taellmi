import Foundation

/// Words in a thought that name a Concept (a Mention), with where they sit in the Text.
public struct ConceptMention: Sendable, Equatable {
    /// A Concept kind from config: person, place, topic, emotion, …
    public var kind: String
    /// The Concept's name. Only identical names (ignoring case) are the same Concept (ADR 0012).
    public var name: String
    public var utf16Range: Range<Int>

    public init(kind: String, name: String, utf16Range: Range<Int>) {
        self.kind = kind
        self.name = name
        self.utf16Range = utf16Range
    }
}

/// What a model made of one thought: an optional one-sentence summary and the Concepts it mentions.
public struct Understanding: Sendable, Equatable {
    public var summary: String?
    public var mentions: [ConceptMention]

    public init(summary: String?, mentions: [ConceptMention]) {
        self.summary = summary
        self.mentions = mentions
    }
}

/// Turns a model's list of concepts into Mentions of your own words. A concept whose words don't appear in
/// the thought is dropped: everything shown must point back to what you said (ADR 0006).
public enum ConceptMentions {
    /// `answer` is `{"concepts": [{"name", "kind", "mention"}]}`, the shape of the concepts prompt.
    public static func locate(in text: String, answer: JSONValue, kinds: Set<String>) -> [ConceptMention] {
        let items = answer.objectValue?["concepts"]?.arrayValue ?? []
        var result: [ConceptMention] = []
        for item in items {
            guard let fields = item.objectValue, let kind = fields["kind"]?.stringValue, kinds.contains(kind),
                let words = fields["mention"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                !words.isEmpty
            else { continue }
            let given = fields["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = given.isEmpty ? words : given
            // The name must be your words too, so nothing is inferred from them (e.g. "traurig" from "geweint").
            guard text.range(of: name, options: .caseInsensitive) != nil else { continue }
            for range in occurrences(of: words, in: text)
            where !result.contains(where: { $0.kind == kind && $0.utf16Range == range }) {
                result.append(ConceptMention(kind: kind, name: name, utf16Range: range))
            }
        }
        return result
    }

    /// Every whole-word, case-insensitive occurrence, as UTF-16 ranges.
    static func occurrences(of words: String, in text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var searchStart = text.startIndex
        while let found = text.range(
            of: words, options: [.caseInsensitive], range: searchStart..<text.endIndex)
        {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            if !(before?.isLetter ?? false), !(after?.isLetter ?? false) {
                let start = text.utf16.distance(from: text.startIndex, to: found.lowerBound)
                let end = text.utf16.distance(from: text.startIndex, to: found.upperBound)
                ranges.append(start..<end)
            }
            searchStart = found.upperBound
        }
        return ranges
    }
}

/// A Concept across the Archive, with how many thoughts mention it.
public struct ConceptSummary: Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var kind: String
    public var name: String
    public var thoughtCount: Int

    public init(id: String, kind: String, name: String, thoughtCount: Int) {
        self.id = id
        self.kind = kind
        self.name = name
        self.thoughtCount = thoughtCount
    }
}

/// One Concept as one thought mentions it, with every place its words appear.
public struct ThoughtConcept: Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var kind: String
    public var name: String
    public var utf16Ranges: [Range<Int>]

    public init(id: String, kind: String, name: String, utf16Ranges: [Range<Int>]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.utf16Ranges = utf16Ranges
    }
}

/// What tällmi shows next to a thought: its summary (generated, or yours if you edited it), its Concepts
/// and the thoughts closest to it in meaning.
public struct ThoughtMeaning: Sendable, Equatable {
    public var summary: String?
    /// You edited the summary; it is yours now and never regenerated.
    public var summaryIsEdited: Bool
    public var concepts: [ThoughtConcept]
    public var related: [Entry]

    public init(summary: String?, summaryIsEdited: Bool, concepts: [ThoughtConcept], related: [Entry]) {
        self.summary = summary
        self.summaryIsEdited = summaryIsEdited
        self.concepts = concepts
        self.related = related
    }

    public static let empty = ThoughtMeaning(summary: nil, summaryIsEdited: false, concepts: [], related: [])
}

/// A Concept and everything connected to it.
public struct ConceptDetail: Sendable, Equatable {
    public var concept: ConceptSummary
    /// Thoughts that mention it, newest first.
    public var thoughts: [Entry]
    /// Concepts mentioned in the same thoughts, most shared first.
    public var appearingWith: [ConceptSummary]

    public init(concept: ConceptSummary, thoughts: [Entry], appearingWith: [ConceptSummary]) {
        self.concept = concept
        self.thoughts = thoughts
        self.appearingWith = appearingWith
    }
}

/// A kind of Concept as config describes it: the word users see for many of them and its symbol.
public struct ConceptKind: Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    /// e.g. "people", "feelings" (docs/brand.md: concepts are shown by kind).
    public var plural: String
    /// An SF Symbol name.
    public var symbol: String

    public init(id: String, plural: String, symbol: String) {
        self.id = id
        self.plural = plural
        self.symbol = symbol
    }
}
