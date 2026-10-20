import Domain
import Foundation

/// A deterministic embedder for tests: texts that share letter sequences get similar vectors, so
/// "Angst" lands near "Zukunftsangst" and far from "Fahrrad". Records how it was used.
public actor FakeEmbedder: Embedder {
    public struct Failure: Error, Equatable {
        public init() {}
    }

    public static let dimensions = 64

    public private(set) var calls: [(texts: [String], purpose: EmbeddingPurpose)] = []
    public private(set) var unloadCalls = 0
    private var failuresRemaining: Int

    public init(failTimes: Int = 0) {
        failuresRemaining = failTimes
    }

    public func embed(_ texts: [String], purpose: EmbeddingPurpose) async throws -> [[Float]] {
        calls.append((texts, purpose))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Failure()
        }
        return texts.map(Self.vector)
    }

    public func unload() async {
        unloadCalls += 1
    }

    public var embeddedTexts: [String] { calls.filter { $0.purpose == .document }.flatMap(\.texts) }

    /// Letter trigrams of each word, hashed into a fixed number of buckets, then normalised.
    public static func vector(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            let letters = Array(" \(word) ")
            guard letters.count >= 3 else { continue }
            for start in 0...(letters.count - 3) {
                vector[Int(fnv1a(String(letters[start..<start + 3])) % UInt64(dimensions))] += 1
            }
        }
        let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return length > 0 ? vector.map { $0 / length } : vector
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
