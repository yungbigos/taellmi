import Config
import Domain
import Foundation
import Persistence
import SearchEvaluation
import TestSupport
import Testing

@Suite("Evaluating search on a set")
struct SearchEvaluatorTests {
    private let set = EvalSet(
        name: "mini",
        documents: [
            .init(id: "worry", text: "Ich habe Angst vor der Zukunft."),
            .init(id: "bike", text: "Fahrrad repariert, Kette geölt."),
            .init(id: "words", text: "Zukunftsangst ist ein langes Wort."),
        ],
        queries: [
            .init(id: "q1", text: "Zukunftsangst", kind: "part", relevant: ["worry", "words"]),
            .init(id: "q2", text: "Fahrrad", kind: "exact", relevant: ["bike"]),
            .init(id: "q3", text: "Segeltörn", kind: "none", relevant: []),
        ])

    private func evaluator(_ folder: TemporaryDirectory) -> SearchEvaluator {
        let models = folder.url.appendingPathComponent("models")
        return SearchEvaluator(
            engines: ["fake_engine", "fake_embedder"], installation: ModelInstallation(root: models),
            embedders: FakeEmbedderProvider(), scratch: folder.url.appendingPathComponent("scratch"),
            seed: { database in
                _ = try seedFakeTranscription(database, modelsRoot: models)
                try ConfigEditor(database: database).setSetting(SettingKeys.searchMinSimilarity, to: .number(0.3))
            })
    }

    @Test("meaning search finds what words alone miss, and the scores say so")
    func meaningVersusWords() async throws {
        let folder = try TemporaryDirectory()
        let evaluator = evaluator(folder)
        let words = try await evaluator.run(set, variant: .init(name: "words", meaning: false))
        let hybrid = try await evaluator.run(set, variant: .init(name: "hybrid"))

        #expect(words.overall.answerable == 2)
        #expect(words.overall.unanswerable == 1)
        #expect(words.overall.recallAt5 == 0.75)
        #expect(hybrid.overall.recallAt5 == 1)
        #expect(hybrid.passages == 3)
        #expect(hybrid.byKind.map(\.kind) == ["exact", "none", "part"])
    }

    @Test("a variant's settings apply: a strict threshold leaves only word matches")
    func variantSettings() async throws {
        let folder = try TemporaryDirectory()
        let strict = try await evaluator(folder).run(
            set, variant: .init(name: "strict", settings: [SettingKeys.searchMinSimilarity: .number(0.999)]))
        #expect(strict.overall.recallAt5 == 0.75)
        #expect(strict.overall.falseMatchRate == 0)
    }

    @Test("the scratch database is removed afterwards")
    func cleansUp() async throws {
        let folder = try TemporaryDirectory()
        _ = try await evaluator(folder).run(set, variant: .init(name: "hybrid"))
        let left = try FileManager.default.contentsOfDirectory(
            atPath: folder.url.appendingPathComponent("scratch").path)
        #expect(left.isEmpty)
    }

    @Test("a set loads from its two files, with an evenly spread sample of searches")
    func loads() throws {
        let folder = try TemporaryDirectory()
        try #"{"id": "a", "text": "Eins.", "date": "2026-01-02T08:14:00"}"#.write(
            to: folder.url.appendingPathComponent("corpus.jsonl"), atomically: true, encoding: .utf8)
        try (0..<10).map { #"{"id": "q\#($0)", "text": "x", "kind": "exact", "relevant": ["a"]}"# }
            .joined(separator: "\n")
            .write(to: folder.url.appendingPathComponent("queries.jsonl"), atomically: true, encoding: .utf8)
        let loaded = try EvalSet.load(from: folder.url, maxQueries: 5)
        #expect(loaded.documents.first?.date != nil)
        #expect(loaded.queries.map(\.id) == ["q0", "q2", "q4", "q6", "q8"])
    }
}
