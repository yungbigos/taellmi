import Foundation

/// Standard ranking scores for evaluating search against known right answers.
public enum EvalMetrics {
    /// Share of the right answers that appear in the first `k` results.
    public static func recall(_ results: [String], relevant: Set<String>, at k: Int) -> Double {
        guard !relevant.isEmpty else { return 0 }
        return Double(Set(results.prefix(k)).intersection(relevant).count) / Double(relevant.count)
    }

    /// Share of the first `k` places taken by right answers; empty places count as wrong, so the score reflects
    /// what fills a screen of results.
    public static func precision(_ results: [String], relevant: Set<String>, at k: Int) -> Double {
        Double(results.prefix(k).filter(relevant.contains).count) / Double(k)
    }

    /// 1 / position of the first right answer, or 0 if none appears within `cutoff`.
    public static func reciprocalRank(_ results: [String], relevant: Set<String>, cutoff: Int) -> Double {
        guard let index = results.prefix(cutoff).firstIndex(where: relevant.contains) else { return 0 }
        return 1 / Double(index + 1)
    }

    /// Normalised discounted cumulative gain: rewards right answers near the top, 1 for a perfect ranking.
    public static func ndcg(_ results: [String], relevant: Set<String>, at k: Int) -> Double {
        func gain(_ position: Int) -> Double { 1 / log2(Double(position + 2)) }
        let dcg = results.prefix(k).enumerated().reduce(0) {
            $0 + (relevant.contains($1.element) ? gain($1.offset) : 0)
        }
        let ideal = (0..<min(k, relevant.count)).reduce(0) { $0 + gain($1) }
        return ideal > 0 ? dcg / ideal : 0
    }

    /// What one search returned, and what it should have found (empty: nothing should be found).
    public struct Outcome: Sendable {
        public var results: [String]
        public var relevant: Set<String>

        public init(results: [String], relevant: Set<String>) {
            self.results = results
            self.relevant = relevant
        }
    }

    public struct Summary: Sendable {
        public var answerable = 0
        public var unanswerable = 0
        public var recallAt5 = 0.0
        public var recallAt10 = 0.0
        public var precisionAt10 = 0.0
        public var mrrAt10 = 0.0
        public var ndcgAt10 = 0.0
        /// Share of searches without a right answer that still returned something.
        public var falseMatchRate = 0.0
        /// Average number of results per search.
        public var averageResults = 0.0

        public init(outcomes: [Outcome]) {
            let answerable = outcomes.filter { !$0.relevant.isEmpty }
            let unanswerable = outcomes.filter { $0.relevant.isEmpty }
            self.answerable = answerable.count
            self.unanswerable = unanswerable.count
            func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
            recallAt5 = mean(answerable.map { EvalMetrics.recall($0.results, relevant: $0.relevant, at: 5) })
            recallAt10 = mean(answerable.map { EvalMetrics.recall($0.results, relevant: $0.relevant, at: 10) })
            precisionAt10 = mean(answerable.map { EvalMetrics.precision($0.results, relevant: $0.relevant, at: 10) })
            mrrAt10 = mean(answerable.map { EvalMetrics.reciprocalRank($0.results, relevant: $0.relevant, cutoff: 10) })
            ndcgAt10 = mean(answerable.map { EvalMetrics.ndcg($0.results, relevant: $0.relevant, at: 10) })
            falseMatchRate = mean(unanswerable.map { $0.results.isEmpty ? 0 : 1 })
            averageResults = mean(outcomes.map { Double($0.results.count) })
        }
    }
}
