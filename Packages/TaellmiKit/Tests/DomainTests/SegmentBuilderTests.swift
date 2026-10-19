import Domain
import Testing

@Suite("Segment builder")
struct SegmentBuilderTests {
    private func token(_ text: String, _ start: Double, _ end: Double) -> TimedToken {
        TimedToken(text: text, start: start, end: end)
    }

    @Test("joins word-piece tokens into readable text")
    func joinsWordPieces() {
        let tokens = [
            token("▁Ich", 0.0, 0.2), token("▁war", 0.2, 0.4), token("▁heute", 0.4, 0.7),
            token("▁im", 0.7, 0.8), token("▁Büro", 0.8, 1.1), token(".", 1.1, 1.15),
        ]
        let segments = SegmentBuilder(maxPause: 1.5).segments(from: tokens)
        #expect(segments.map(\.text) == ["Ich war heute im Büro."])
        #expect(segments.first?.startMs == 0)
        #expect(segments.first?.endMs == 1150)
    }

    @Test("splits at sentence-ending punctuation")
    func splitsAtSentenceEnd() {
        let tokens = [
            token("▁Das", 0.0, 0.2), token("▁war", 0.2, 0.4), token("▁gut", 0.4, 0.6), token("!", 0.6, 0.65),
            token("▁Honestly", 0.9, 1.3), token(",", 1.3, 1.32), token("▁great", 1.4, 1.7), token(".", 1.7, 1.72),
        ]
        let segments = SegmentBuilder(maxPause: 1.5).segments(from: tokens)
        #expect(segments.map(\.text) == ["Das war gut!", "Honestly, great."])
        #expect(segments[1].startMs == 900)
    }

    @Test("splits at long pauses even without punctuation")
    func splitsAtPauses() {
        let tokens = [token("▁also", 0.0, 0.3), token("▁ähm", 0.3, 0.6), token("▁Zukunftsangst", 3.0, 3.8)]
        let segments = SegmentBuilder(maxPause: 1.5).segments(from: tokens)
        #expect(segments.map(\.text) == ["also ähm", "Zukunftsangst"])
    }

    @Test("word pieces without a boundary marker attach to the previous word")
    func attachesSubwordPieces() {
        let tokens = [token("▁Zukunft", 0.0, 0.3), token("s", 0.3, 0.35), token("angst", 0.35, 0.6)]
        #expect(SegmentBuilder(maxPause: 1.5).segments(from: tokens).map(\.text) == ["Zukunftsangst"])
    }

    @Test("a leading space marks a word boundary too (FluidAudio's token format)")
    func leadingSpaceBoundary() {
        let tokens = [
            token(" Guten", 0.0, 0.3), token(" Mor", 0.3, 0.5), token("gen", 0.5, 0.7), token(".", 0.7, 0.75),
        ]
        #expect(SegmentBuilder(maxPause: 1.5).segments(from: tokens).map(\.text) == ["Guten Morgen."])
    }

    @Test("no tokens gives no segments")
    func empty() {
        #expect(SegmentBuilder(maxPause: 1.5).segments(from: []).isEmpty)
    }
}
