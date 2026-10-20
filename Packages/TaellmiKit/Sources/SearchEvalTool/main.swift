import Config
import Domain
import Foundation
import MLXEmbedderEngine
import SearchEvaluation

// Measures search on evaluation sets with the real embedding model and writes a Markdown report.
//   SearchEvalTool --models <dir> --metallib <file> --out <report.md> --set <folder>[:maxQueries] …
// Run through scripts/eval-search.sh, which prepares the sets and the Metal shaders.

struct Arguments {
    var models: URL?
    var metallib: URL?
    var out: URL?
    var sets: [(URL, Int?)] = []

    init(_ arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let flag = iterator.next(), let value = iterator.next() {
            switch flag {
            case "--models": models = URL(fileURLWithPath: value)
            case "--metallib": metallib = URL(fileURLWithPath: value)
            case "--out": out = URL(fileURLWithPath: value)
            case "--set":
                let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
                sets.append((URL(fileURLWithPath: parts[0]), parts.count > 1 ? Int(parts[1]) : nil))
            default: break
            }
        }
    }
}

struct SingleEmbedder: EmbedderProvider {
    let embedder: MLXEmbedder
    func acquireEmbedder(_ model: ModelConfig) async throws -> any Embedder { embedder }
    func release(_ model: ModelConfig) async {}
}

let variants: [EvalVariant] = [
    .init(name: "F: passages 600, min 0.50", settings: [SettingKeys.searchMinSimilarity: .number(0.50)]),
    .init(name: "G: passages 600, min 0.55", settings: [SettingKeys.searchMinSimilarity: .number(0.55)]),
    .init(name: "H: passages 600, min 0.60", settings: [SettingKeys.searchMinSimilarity: .number(0.60)]),
    .init(name: "words only", meaning: false),
    .init(name: "A: passages 600, min 0.35 (current)"),
    .init(
        name: "B: passages 250, min 0.35",
        settings: [SettingKeys.fragmentTargetLength: .number(250), SettingKeys.fragmentMaxLength: .number(500)]),
    .init(name: "C: passages 600, min 0.45", settings: [SettingKeys.searchMinSimilarity: .number(0.45)]),
    .init(
        name: "D: passages 600, min 0.35, window 0.10",
        settings: [SettingKeys.searchRelativeSimilarityWindow: .number(0.1)]),
    .init(
        name: "E: passages 250, min 0.35, window 0.10",
        settings: [
            SettingKeys.fragmentTargetLength: .number(250), SettingKeys.fragmentMaxLength: .number(500),
            SettingKeys.searchRelativeSimilarityWindow: .number(0.1),
        ]),
]

// Line by line, so progress shows up in a log file while a long run is going.
setvbuf(stdout, nil, _IOLBF, 0)

let arguments = Arguments(CommandLine.arguments)
guard let models = arguments.models, let out = arguments.out, !arguments.sets.isEmpty else {
    FileHandle.standardError.write(
        Data("usage: SearchEvalTool --models <dir> --metallib <file> --out <md> --set <dir>[:n]\n".utf8))
    exit(2)
}
if let metallib = arguments.metallib { MLXEmbedder.useMetalShaders(at: metallib) }

let bundle = try SeedBundle.bundled()
guard
    let modelSeed = bundle.models.first(where: {
        $0.engine == MLXEmbedder.engineKey && $0.capabilities.contains("embed")
    })
else { fatalError("no MLX embedding model in the seeds") }
let installation = ModelInstallation(root: models)
let embedder = MLXEmbedder(
    directory: installation.directory(
        for: ModelConfig(
            id: modelSeed.id, name: modelSeed.name, engine: modelSeed.engine, providerID: modelSeed.providerID)),
    options: try MLXEmbedderOptions(params: modelSeed.params))
let evaluator = SearchEvaluator(
    engines: [MLXEmbedder.engineKey], installation: installation, embedders: SingleEmbedder(embedder: embedder),
    scratch: FileManager.default.temporaryDirectory.appendingPathComponent("taellmi-eval"),
    progress: { line in if line.hasSuffix("passages"), line.contains("/") { print("    " + line) } },
    seed: { database in _ = try Seeder(database: database).apply(bundle) })

func pct(_ value: Double) -> String { String(format: "%.1f", value * 100) }
var report =
    "# Search evaluation\n\nModel: `\(modelSeed.id)` (\(modelSeed.params["dimensions"]?.doubleValue.map { Int($0) } ?? 0) dims). "
report +=
    "Scores in %, higher is better, except false matches (share of searches with no right answer that still returned something).\n"
for (folder, maxQueries) in arguments.sets {
    let set = try EvalSet.load(from: folder, maxQueries: maxQueries)
    print("▸ \(set.name): \(set.documents.count) documents, \(set.queries.count) searches")
    report += "\n## \(set.name): \(set.documents.count) documents, \(set.queries.count) searches\n\n"
    report +=
        "| variant | passages | P@10 | R@5 | R@10 | MRR@10 | nDCG@10 | false matches | results/search | ms/search |\n|---|---|---|---|---|---|---|---|---|---|\n"
    var kindRows: [String] = []
    var lastBest: (answerable: [Double], unanswerable: [Double])?
    var lastMargin: (answerable: [Double], unanswerable: [Double])?
    var kinds: [String] = []
    for variant in variants {
        let result = try await evaluator.run(set, variant: variant)
        let o = result.overall
        if variant.meaning {
            lastBest = result.bestSimilarity
            lastMargin = result.bestMargin
        }
        print(
            "  \(variant.name): P@10 \(pct(o.precisionAt10)) R@5 \(pct(o.recallAt5)) MRR \(pct(o.mrrAt10)) false \(pct(o.falseMatchRate))"
        )
        report +=
            "| \(variant.name) | \(result.passages) | \(pct(o.precisionAt10)) | \(pct(o.recallAt5)) | \(pct(o.recallAt10)) | \(pct(o.mrrAt10)) | \(pct(o.ndcgAt10)) | "
        report +=
            (o.unanswerable > 0 ? pct(o.falseMatchRate) : "–")
            + " | \(String(format: "%.1f", o.averageResults)) | \(String(format: "%.0f", result.millisecondsPerSearch)) |\n"
        try (report + "\n_(run in progress)_\n").write(to: out, atomically: true, encoding: .utf8)
        if result.byKind.count > 1 {
            kinds = result.byKind.map(\.kind)
            kindRows.append(
                "| \(variant.name) | "
                    + result.byKind.map {
                        $0.summary.answerable > 0 ? pct($0.summary.mrrAt10) : pct($0.summary.falseMatchRate) + " false"
                    }.joined(separator: " | ") + " |")
        }
    }
    if let sims = lastBest, !sims.unanswerable.isEmpty {
        func q(_ values: [Double], _ p: Double) -> String {
            let sorted = values.sorted()
            return String(format: "%.2f", sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))])
        }
        report +=
            "\nSimilarity of the closest passage (10th / 50th / 90th percentile):\n\n| searches | n | p10 | p50 | p90 |\n|---|---|---|---|---|\n"
        report +=
            "| with an answer | \(sims.answerable.count) | \(q(sims.answerable, 0.1)) | \(q(sims.answerable, 0.5)) | \(q(sims.answerable, 0.9)) |\n"
        report +=
            "| without an answer | \(sims.unanswerable.count) | \(q(sims.unanswerable, 0.1)) | \(q(sims.unanswerable, 0.5)) | \(q(sims.unanswerable, 0.9)) |\n"
        if let m = lastMargin {
            report +=
                "| margin, with an answer | \(m.answerable.count) | \(q(m.answerable, 0.1)) | \(q(m.answerable, 0.5)) | \(q(m.answerable, 0.9)) |\n"
            report +=
                "| margin, without an answer | \(m.unanswerable.count) | \(q(m.unanswerable, 0.1)) | \(q(m.unanswerable, 0.5)) | \(q(m.unanswerable, 0.9)) |\n"
        }
        report +=
            "\nWithout an answer, sorted: "
            + sims.unanswerable.sorted().map { String(format: "%.2f", $0) }.joined(separator: " ") + "\n"
    }
    if !kindRows.isEmpty {
        report +=
            "\nMRR@10 by kind of search (for `none`: false-match rate):\n\n| variant | "
            + kinds.joined(separator: " | ") + " |\n|" + String(repeating: "---|", count: kinds.count + 1) + "\n"
            + kindRows.joined(separator: "\n") + "\n"
    }
}
try report.write(to: out, atomically: true, encoding: .utf8)
print("✔ report: \(out.path)")
