import Foundation

/// Groups engine tokens into readable segments, split at sentence ends and long pauses.
public struct SegmentBuilder: Sendable {
    /// Word-start markers: SentencePiece's "▁", or a plain space once an engine has normalised it.
    private static let wordBoundaries: Set<Character> = ["▁", " "]
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]

    /// Seconds of silence after which a new segment starts. Comes from config.
    public var maxPause: TimeInterval

    public init(maxPause: TimeInterval) {
        self.maxPause = maxPause
    }

    public func segments(from tokens: [TimedToken]) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                segments.append(
                    TranscriptSegment(startMs: Self.ms(start), endMs: Self.ms(end), text: trimmed))
            }
            text = ""
        }

        for token in tokens {
            if !text.isEmpty, token.start - end > maxPause { flush() }
            if text.isEmpty { start = token.start }
            if let first = token.text.first, Self.wordBoundaries.contains(first) {
                text += " " + token.text.dropFirst()
            } else {
                text += token.text
            }
            end = token.end
            if let last = token.text.last, Self.sentenceEnders.contains(last) { flush() }
        }
        flush()
        return segments
    }

    private static func ms(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1000).rounded())
    }
}
