import Domain
import Foundation

/// What every embedding engine must do, checked the same way for the fake and for real models.
/// Returns the problems found; empty means the engine keeps the contract.
public enum EmbedderContract {
    public static let germanTexts = [
        "Ich habe Angst vor der Zukunft.", "Fahrrad repariert, Kette geölt.", "Marleen kommt am Wochenende.",
    ]

    public static func problems(of embedder: any Embedder, dimensions: Int) async throws -> [String] {
        var problems: [String] = []
        if try await !embedder.embed([], purpose: .document).isEmpty {
            problems.append("no texts must give no vectors")
        }
        let vectors = try await embedder.embed(germanTexts, purpose: .document)
        if vectors.count != germanTexts.count { problems.append("one vector per text, in order") }
        for vector in vectors {
            if vector.count != dimensions { problems.append("vector size \(vector.count), expected \(dimensions)") }
            let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            if abs(length - 1) > 0.01 { problems.append("vectors must have unit length, got \(length)") }
        }
        let again = try await embedder.embed([germanTexts[0]], purpose: .document)
        if let first = vectors.first, let repeated = again.first, cosine(first, repeated) < 0.999 {
            problems.append("the same text must give the same vector, also alone instead of in a batch")
        }
        await embedder.unload()
        let afterUnload = try await embedder.embed([germanTexts[0]], purpose: .document)
        if afterUnload.first?.count != dimensions { problems.append("must load again after unload") }
        return problems
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
