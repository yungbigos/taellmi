import Domain
import Persistence
import TestSupport
import Testing

@Suite("Keyword relevance")
struct KeywordScoreTests {
    @Test("an Entry that uses the search words more often ranks higher; others get no score")
    func ranksByRelevance() throws {
        let index = EntryIndex(database: try makeDatabase())
        for (id, text) in [
            ("often", "Zukunftsangst, wieder Zukunftsangst. Die Angst ist groß."),
            ("once", "Heute im Büro, ein bisschen Zukunftsangst und viele Meetings über das Budget."),
            ("never", "Fahrrad repariert."),
        ] {
            try index.upsert(
                Entry(id: id, createdAt: sampleDate, durationSeconds: nil, source: .typed, folder: id, text: text),
                transcript: nil)
        }
        let scores = try index.keywordScores(words: ["angst"])
        #expect(Set(scores.keys) == ["often", "once"])
        #expect(try #require(scores["often"]) > (try #require(scores["once"])))
    }

    @Test("words shorter than three letters give no score instead of failing")
    func shortWords() throws {
        let index = EntryIndex(database: try makeDatabase())
        #expect(try index.keywordScores(words: ["ok"]).isEmpty)
    }
}
