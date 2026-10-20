import Domain
import Foundation
import MLX
import MLXEmbedderEngine
import TestSupport
import Testing

/// Runs the real embedding model on German sentences. Needs the model downloaded
/// (scripts/download-model.sh qwen3-embedding-0.6b-8bit) and MLX's Metal shaders
/// (scripts/test-integration.sh finds them); skipped by the fast gate.
@Suite("MLX embedder on real text", .enabled(if: MLXEmbedderFixture.isAvailable), .serialized)
struct MLXEmbedderIntegrationTests {
    private func makeEmbedder() throws -> MLXEmbedder {
        MLXEmbedderFixture.useMetalShaders()
        return MLXEmbedder(
            directory: MLXEmbedderFixture.modelDirectory,
            options: try MLXEmbedderOptions(params: [
                "dimensions": .number(512), "pooling": .string("last"),
                "query_template": .string(
                    "Instruct: Given a question or keywords, find passages of a personal journal that answer or match it\nQuery:{{query}}"
                ),
            ]))
    }

    @Test("keeps the embedder contract")
    func contract() async throws {
        #expect(try await EmbedderContract.problems(of: try makeEmbedder(), dimensions: 512) == [])
    }

    @Test("a German query lands closest to the passage that means it, also across compounds and English")
    func meaning() async throws {
        let embedder = try makeEmbedder()
        let passages = [
            "Ich habe Angst vor der Zukunft und weiß nicht, wie es weitergeht.",
            "Fahrrad repariert, die Kette war total verrostet.",
            "Meeting mit dem Team, honestly ziemlich anstrengend.",
        ]
        let documents = try await embedder.embed(passages, purpose: .document)
        for (query, expected) in [("Zukunftsangst", 0), ("bike", 1), ("Arbeit war stressig", 2)] {
            let vector = try #require(try await embedder.embed([query], purpose: .query).first)
            let similarities = documents.map { EmbedderContract.cosine(vector, $0) }
            let best = try #require(similarities.indices.max { similarities[$0] < similarities[$1] })
            #expect(best == expected, "\(query): \(similarities)")
        }
        await embedder.unload()
    }

    /// The seeded `search.min_similarity` (0.35) was measured with this model: short everyday queries reach
    /// their thought at about 0.39 or more, unrelated thoughts stay at about 0.32 or less.
    @Test("the seeded similarity threshold keeps short real matches and drops unrelated thoughts")
    func threshold() async throws {
        let embedder = try makeEmbedder()
        let threshold: Float = 0.35
        let passages = [
            "Mutti hat angerufen, sie hat nächste Woche Geburtstag.",
            "Fahrrad repariert, die Kette war total verrostet.",
            "Heute an der Isar spazieren, die Sonne war schön.",
        ]
        let documents = try await embedder.embed(passages, purpose: .document)
        for (query, expected) in [("Mama", 0), ("bike", 1), ("Spaziergang", 2)] {
            let vector = try #require(try await embedder.embed([query], purpose: .query).first)
            #expect(EmbedderContract.cosine(vector, documents[expected]) >= threshold, "\(query) must be found")
        }
        let unrelated = try #require(try await embedder.embed(["Steuererklärung"], purpose: .query).first)
        for document in documents {
            #expect(EmbedderContract.cosine(unrelated, document) < threshold, "unrelated thoughts must not show")
        }
        await embedder.unload()
    }
}

extension MLXEmbedderIntegrationTests {
    /// Typing in search sends a request per keystroke, often while the model is still loading.
    @Test("requests that arrive together while the model loads get the same, correct answer")
    func concurrentFirstUse() async throws {
        let embedder = try makeEmbedder()
        async let first = embedder.embed(["Wohnung ist kalt"], purpose: .query)
        async let second = embedder.embed(["Wohnung ist kalt"], purpose: .query)
        let (a, b) = try await (first, second)
        let alone = try await embedder.embed(["Wohnung ist kalt"], purpose: .query)
        #expect(EmbedderContract.cosine(a[0], b[0]) > 0.999)
        #expect(EmbedderContract.cosine(a[0], alone[0]) > 0.999)
        await embedder.unload()
    }

    /// Long runs (indexing a whole Archive) once grew MLX's buffer cache to over 20 GB. With the seeded caps,
    /// memory stays bounded however many passages go through.
    @Test("embedding many long passages stays within the configured memory caps")
    func boundedMemory() async throws {
        MLXEmbedderFixture.useMetalShaders()
        let embedder = MLXEmbedder(
            directory: MLXEmbedderFixture.modelDirectory,
            options: try MLXEmbedderOptions(params: [
                "dimensions": .number(512), "pooling": .string("last"), "cache_limit_mb": .number(256),
                "memory_limit_mb": .number(2048),
            ]))
        let sentence =
            "Heute war ein langer Tag im Büro, das Meeting mit Sven hat ewig gedauert und danach war ich an der Isar. "
        for round in 0..<12 {
            let batch = (0..<32).map { String(repeating: sentence, count: 3 + ($0 + round) % 9) }
            _ = try await embedder.embed(batch, purpose: .document)
        }
        let megabytes = (Memory.activeMemory + Memory.cacheMemory) / 1024 / 1024
        #expect(megabytes < 2048, "MLX holds \(megabytes) MB after the run")
        // The cap is soft by design: the cache may overshoot by its last buffer.
        #expect(Double(Memory.cacheMemory) <= 256 * 1024 * 1024 * 1.1)
        await embedder.unload()
    }
}

enum MLXEmbedderFixture {
    /// Defaults to the sandboxed app's model folder; override with TAELLMI_MODELS_DIR.
    static var modelDirectory: URL {
        let root =
            ProcessInfo.processInfo.environment["TAELLMI_MODELS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/app.taellmi/Data/Library/Application Support/taellmi/models")
        return root.appendingPathComponent("qwen3-embedding-0.6b-8bit")
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent(".taellmi-verified").path)
            && ProcessInfo.processInfo.environment["TAELLMI_MLX_METALLIB"] != nil
    }

    /// `swift test` cannot build MLX's Metal shaders; the integration script points at the ones Xcode built.
    static func useMetalShaders() {
        if let path = ProcessInfo.processInfo.environment["TAELLMI_MLX_METALLIB"] {
            GPU.metallib = URL(fileURLWithPath: path)
        }
    }
}
