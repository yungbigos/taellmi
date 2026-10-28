import Config
import Domain
import Features
import Foundation
import Persistence
import TestSupport
import Testing

@testable import AppComposition

@Suite("Downloading the voice models in the assembled app")
struct VoiceDownloadTests {
    static let revision = "0123456789abcdef0123456789abcdef01234567"
    static let speechWeights = Data("Gewichte für die Spracherkennung, äh, ziemlich groß".utf8)
    static let meaningWeights = Data("Bedeutung: Straße, Grüße, meeting notes".utf8)

    static func url(_ repo: String, _ path: String) -> String {
        "https://huggingface.co/\(repo)/resolve/\(revision)/\(path)"
    }

    static let everything = [
        url("kim/sprache", "weights.bin"): speechWeights, url("sam/bedeutung", "model.safetensors"): meaningWeights,
    ]

    /// An app whose speech and meaning roles are assigned first to two small test downloads from Hugging Face.
    private func makeEnvironment(serving files: [String: Data]) throws -> (
        AppEnvironment, FakeModelFetcher, TemporaryDirectory, TemporaryDirectory
    ) {
        let home = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let fetcher = FakeModelFetcher(files: files)
        let environment = try AppEnvironment(
            paths: AppPaths(root: home.url), engines: ["fake_engine": { _, _ in FakeTranscriber() }],
            recorder: FakeRecorder(folder: scratch.url), fetcher: fetcher)
        var bundle = try SeedBundle.bundled()
        bundle.models.append(
            .init(
                id: "kim-sprache", name: "Kim Sprache", engine: "fake_engine", providerID: "huggingface",
                sourceRef: "kim/sprache", revision: Self.revision,
                files: [
                    ModelFile(
                        path: "weights.bin", sha256: sha256Hex(Self.speechWeights), bytes: Self.speechWeights.count)
                ],
                capabilities: ["transcription"]))
        bundle.models.append(
            .init(
                id: "sam-bedeutung", name: "Sam Bedeutung", engine: "fake_embedder", providerID: "huggingface",
                sourceRef: "sam/bedeutung", revision: Self.revision,
                files: [
                    ModelFile(
                        path: "model.safetensors", sha256: sha256Hex(Self.meaningWeights),
                        bytes: Self.meaningWeights.count)
                ],
                capabilities: ["embed"]))
        bundle.assignments.append(.init(id: "test-speech", role: "transcription", priority: -1, modelID: "kim-sprache"))
        bundle.assignments.append(.init(id: "test-meaning", role: "embed", priority: -1, modelID: "sam-bedeutung"))
        _ = try Seeder(database: environment.database).apply(bundle)
        return (environment, fetcher, home, scratch)
    }

    private func follow(_ environment: AppEnvironment) async -> [VoiceSetup] {
        var seen: [VoiceSetup] = []
        for await setup in environment.downloadVoiceModels() { seen.append(setup) }
        return seen
    }

    @Test("download fetches each missing model in turn, speech first, and both are on this mac afterwards")
    func downloadsInTurn() async throws {
        let (environment, fetcher, home, scratch) = try makeEnvironment(serving: Self.everything)
        defer { withExtendedLifetime((home, scratch)) {} }
        #expect(try environment.voiceSetup().downloads.map(\.state) == [.missing, .missing])

        let seen = await follow(environment)

        #expect(
            fetcher.requested.map(\.absoluteString) == [
                Self.url("kim/sprache", "weights.bin"), Self.url("sam/bedeutung", "model.safetensors"),
            ])
        #expect(seen.contains { $0.downloads.map(\.state).last == .waiting })
        #expect(seen.last?.downloads.map(\.state) == [.installed, .installed])
        #expect(try environment.voiceSetup().downloads.map(\.state) == [.installed, .installed])
    }

    @Test("a model whose files don't arrive says so, and the next one still downloads")
    func failureMovesOn() async throws {
        let (environment, _, home, scratch) = try makeEnvironment(serving: [
            Self.url("sam/bedeutung", "model.safetensors"): Self.meaningWeights
        ])
        defer { withExtendedLifetime((home, scratch)) {} }

        let seen = await follow(environment)

        #expect(seen.last?.downloads.map(\.state) == [.failed, .installed])
        #expect(try environment.voiceSetup().downloads.map(\.state) == [.failed, .installed])
    }

    @Test("asking again while it runs follows the same download instead of starting another")
    func joinsRunning() async throws {
        let (environment, fetcher, home, scratch) = try makeEnvironment(serving: Self.everything)
        defer { withExtendedLifetime((home, scratch)) {} }

        let first = environment.downloadVoiceModels()
        let second = environment.downloadVoiceModels()
        for await _ in first {}
        var last: VoiceSetup?
        for await setup in second { last = setup }

        #expect(fetcher.requested.count == 2)
        #expect(last?.downloads.map(\.state) == [.installed, .installed])
    }

    @Test("a spoken thought that waited for speech gets its text as soon as the download is done")
    func waitingThoughtGetsText() async throws {
        let (environment, _, home, scratch) = try makeEnvironment(serving: Self.everything)
        defer { withExtendedLifetime((home, scratch)) {} }
        try await environment.start()
        let entry = try await environment.journal.addVoiceEntry(
            Recording(file: try scratch.makeAudioFile(), durationSeconds: 3.4, startedAt: sampleDate))
        await environment.waitForPipeline()
        #expect(try await environment.journal.recentEntries(limit: 5).first { $0.id == entry.id }?.text == "")

        _ = await follow(environment)
        await environment.waitForPipeline()

        let stored = try await environment.journal.recentEntries(limit: 5).first { $0.id == entry.id }
        #expect(stored?.text == FakeTranscriber.germanResult.text)
    }
}
