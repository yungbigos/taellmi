import Foundation

/// One search result: a thought, how it was found, and where in its Text the match is.
public struct SearchHit: Sendable, Equatable, Identifiable {
    public enum Match: Sendable, Equatable {
        /// Contains every search word: a result.
        case words
        /// Close in meaning only: shown as related, never claimed as an answer.
        case related
    }

    public var entry: Entry
    public var match: Match
    /// Where the search words occur in the Text, as UTF-16 ranges (empty without search words).
    public var wordRanges: [Range<Int>]
    /// For a related thought: the passage that matched by meaning, as a UTF-16 range in the Text.
    public var passage: Range<Int>?

    public var id: String { entry.id }

    public init(entry: Entry, match: Match, wordRanges: [Range<Int>] = [], passage: Range<Int>? = nil) {
        self.entry = entry
        self.match = match
        self.wordRanges = wordRanges
        self.passage = passage
    }
}
