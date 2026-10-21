import Foundation

/// Decides whether a generated summary may be shown: every word in it that says something (noun, name, verb,
/// adjective, adverb) must appear in the thought, in some form. A summary that adds a reason or a feeling the
/// thought doesn't contain is dropped (ADR 0006). It can't catch a shifted nuance made of the thought's own
/// words ("eher müde als genervt" → "müde und genervt"); that limit is accepted.
public enum SummaryGrounding {
    /// - Parameter stemLength: how many leading letters of a word must appear in the thought, so other forms
    ///   of the same word ("anrufen" for "rufe … an" does not count, "Vermieters" for "Vermieter" does) match.
    public static func isGrounded(
        _ summary: String, in thought: String, classifier: any WordClassifier, stemLength: Int
    ) -> Bool {
        let words = classifier.classify(summary).filter(\.carriesMeaning).map { String(summary[$0.range]) }
        guard !words.isEmpty else { return false }
        let haystack = WordsOnlyText(thought).words.lowercased()
        return words.allSatisfy { word in
            let lower = word.lowercased()
            return haystack.contains(String(lower.prefix(max(1, stemLength))))
        }
    }
}
