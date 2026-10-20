import SearchEvaluation
import Testing

@Suite("Search evaluation scores")
struct EvalMetricsTests {
    @Test(
        "recall at k is the share of right answers found in the first k results",
        arguments: [
            (["a", "x", "b"], Set(["a", "b"]), 2, 0.5),
            (["a", "x", "b"], Set(["a", "b"]), 3, 1.0),
            (["x", "y"], Set(["a"]), 5, 0.0),
        ])
    func recall(results: [String], relevant: Set<String>, k: Int, expected: Double) {
        #expect(EvalMetrics.recall(results, relevant: relevant, at: k) == expected)
    }

    @Test(
        "reciprocal rank is one over the position of the first right answer within the cut-off",
        arguments: [
            (["a", "b"], Set(["a"]), 1.0),
            (["x", "y", "a"], Set(["a"]), 1.0 / 3),
            (["x", "y"], Set(["a"]), 0.0),
        ])
    func reciprocalRank(results: [String], relevant: Set<String>, expected: Double) {
        #expect(abs(EvalMetrics.reciprocalRank(results, relevant: relevant, cutoff: 10) - expected) < 1e-9)
    }

    @Test("precision at k is the share of the first k results that are right, counting missing results as wrong")
    func precision() {
        #expect(EvalMetrics.precision(["a", "x", "b", "y"], relevant: ["a", "b", "c"], at: 4) == 0.5)
        #expect(EvalMetrics.precision(["a"], relevant: ["a", "b"], at: 10) == 0.1)
    }

    @Test("a right answer beyond the cut-off does not count")
    func cutoff() {
        #expect(EvalMetrics.reciprocalRank(["x", "y", "a"], relevant: ["a"], cutoff: 2) == 0)
    }

    @Test("nDCG is 1 for a perfect ranking and lower when right answers come later")
    func ndcg() {
        #expect(EvalMetrics.ndcg(["a", "b", "x"], relevant: ["a", "b"], at: 10) == 1)
        let later = EvalMetrics.ndcg(["x", "a", "b"], relevant: ["a", "b"], at: 10)
        #expect(later > 0 && later < 1)
        #expect(EvalMetrics.ndcg(["x"], relevant: ["a"], at: 10) == 0)
    }

    @Test("a summary averages over searches with answers and counts false matches for searches without")
    func summary() {
        let summary = EvalMetrics.Summary(outcomes: [
            .init(results: ["a"], relevant: ["a"]),
            .init(results: ["x", "b"], relevant: ["b"]),
            .init(results: [], relevant: []),
            .init(results: ["x"], relevant: []),
        ])
        #expect(summary.answerable == 2)
        #expect(summary.unanswerable == 2)
        #expect(summary.recallAt5 == 1)
        #expect(abs(summary.mrrAt10 - 0.75) < 1e-9)
        #expect(summary.falseMatchRate == 0.5)
        #expect(abs(summary.precisionAt10 - 0.1) < 1e-9)
    }
}
