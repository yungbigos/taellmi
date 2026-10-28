import Config
import Domain
import Foundation
import Synchronization
import TestSupport
import Testing

@Suite("Downloading a model's pinned files, as scripts/download-model.sh does")
struct ModelDownloaderTests {
    static let revision = "0123456789abcdef0123456789abcdef01234567"
    static let base = URL(string: "https://huggingface.co")!
    static let weights = Data("Gewichte für die Spracherkennung, äh, ziemlich groß".utf8)
    static let vocabulary = Data(#"{"tokens": ["Straße", "Grüße", "meeting"]}"#.utf8)

    static func model(files: [ModelFile]? = nil, revision: String? = Self.revision) -> ModelConfig {
        ModelConfig(
            id: "kim-sprache", name: "Kim Sprache", engine: "fake_engine", providerID: "huggingface",
            sourceRef: "kim/sprache", revision: revision,
            files: files ?? [
                ModelFile(
                    path: "Encoder.mlmodelc/weights/weight.bin", sha256: sha256Hex(weights), bytes: weights.count),
                ModelFile(path: "vocab.json", sha256: sha256Hex(vocabulary), bytes: vocabulary.count),
            ])
    }

    static func url(_ path: String) -> String {
        "https://huggingface.co/kim/sprache/resolve/\(revision)/\(path)"
    }

    static let served = [
        url("Encoder.mlmodelc/weights/weight.bin"): weights, url("vocab.json"): vocabulary,
    ]

    @Test("every file comes from the pinned revision, is checked, and then the model counts as on this mac")
    func downloadsAndMarks() async throws {
        let temp = try TemporaryDirectory()
        let installation = ModelInstallation(root: temp.url)
        let fetcher = FakeModelFetcher(files: Self.served)
        let model = Self.model()

        try await ModelDownloader(installation: installation, fetcher: fetcher)
            .download(model, from: Self.base) { _ in }

        #expect(
            fetcher.requested.map(\.absoluteString) == [
                Self.url("Encoder.mlmodelc/weights/weight.bin"), Self.url("vocab.json"),
            ])
        let folder = installation.directory(for: model)
        #expect(try Data(contentsOf: folder.appending(path: "Encoder.mlmodelc/weights/weight.bin")) == Self.weights)
        #expect(try Data(contentsOf: folder.appending(path: "vocab.json")) == Self.vocabulary)
        #expect(installation.isInstalled(model))
    }

    @Test(
        "a file that doesn't match its fingerprint or size is thrown away, and the model isn't marked",
        arguments: [
            Data("Gewichte für die Spracherkennung, äh, ziemlich grob".utf8),  // same size, other bytes
            Data("Gewichte für die".utf8),  // cut short
        ])
    func refusesMismatch(served: Data) async throws {
        let temp = try TemporaryDirectory()
        let installation = ModelInstallation(root: temp.url)
        var files = Self.served
        files[Self.url("Encoder.mlmodelc/weights/weight.bin")] = served
        let model = Self.model()

        await #expect(throws: ModelDownloadError.mismatch("Encoder.mlmodelc/weights/weight.bin")) {
            try await ModelDownloader(installation: installation, fetcher: FakeModelFetcher(files: files))
                .download(model, from: Self.base) { _ in }
        }
        let weights = installation.directory(for: model).appending(path: "Encoder.mlmodelc/weights")
        #expect(try FileManager.default.contentsOfDirectory(atPath: weights.path).isEmpty)
        #expect(!installation.isInstalled(model))
    }

    @Test("files already here and matching are not fetched again")
    func skipsWhatMatches() async throws {
        let temp = try TemporaryDirectory()
        let installation = ModelInstallation(root: temp.url)
        let model = Self.model()
        let folder = installation.directory(for: model)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.vocabulary.write(to: folder.appending(path: "vocab.json"))
        let fetcher = FakeModelFetcher(files: Self.served)

        try await ModelDownloader(installation: installation, fetcher: fetcher).download(model, from: Self.base) { _ in
        }

        #expect(fetcher.requested.map(\.absoluteString) == [Self.url("Encoder.mlmodelc/weights/weight.bin")])
        #expect(installation.isInstalled(model))
    }

    @Test("a download that fails removes an old mark first, so the model never counts as here by mistake")
    func failureLeavesNoMark() async throws {
        let temp = try TemporaryDirectory()
        let installation = ModelInstallation(root: temp.url)
        let model = Self.model()
        try installation.markVerified(model)

        await #expect(throws: (any Error).self) {
            try await ModelDownloader(installation: installation, fetcher: FakeModelFetcher(files: [:]))
                .download(model, from: Self.base) { _ in }
        }
        #expect(!installation.isInstalled(model))
    }

    @Test(
        "only a model pinned to a revision, with listed files at safe paths, can be downloaded",
        arguments: [
            (Self.model(revision: nil), ModelDownloadError.notDownloadable("kim-sprache")),
            (Self.model(files: []), ModelDownloadError.notDownloadable("kim-sprache")),
            (
                Self.model(files: [ModelFile(path: "../Archive/entry.md", sha256: sha256Hex(weights), bytes: 1)]),
                ModelDownloadError.unsafePath("../Archive/entry.md")
            ),
            (
                Self.model(files: [ModelFile(path: "/etc/hosts", sha256: sha256Hex(weights), bytes: 1)]),
                ModelDownloadError.unsafePath("/etc/hosts")
            ),
        ])
    func refusesUnpinned(model: ModelConfig, error: ModelDownloadError) async throws {
        let temp = try TemporaryDirectory()
        let fetcher = FakeModelFetcher(files: Self.served)
        await #expect(throws: error) {
            try await ModelDownloader(installation: ModelInstallation(root: temp.url), fetcher: fetcher)
                .download(model, from: Self.base) { _ in }
        }
        #expect(fetcher.requested.isEmpty)
    }

    /// Writes the files, but keeps its own handle to each, as a misbehaving downloader could.
    final class LingeringFetcher: ModelFileFetching, Sendable {
        let files: [String: Data]
        let kept = Mutex<[FileHandle]>([])

        init(files: [String: Data]) {
            self.files = files
        }

        func fetch(_ url: URL, into file: FileHandle, progress: @escaping @Sendable (Int64) -> Void) async throws {
            try file.write(contentsOf: files[url.absoluteString] ?? Data())
            let copy = FileHandle(fileDescriptor: dup(file.fileDescriptor), closeOnDealloc: true)
            kept.withLock { $0.append(copy) }
        }
    }

    @Test("a downloader that writes again after it answered can't change a checked file")
    func checkedFilesStayChecked() async throws {
        let temp = try TemporaryDirectory()
        let installation = ModelInstallation(root: temp.url)
        let fetcher = LingeringFetcher(files: Self.served)
        let model = Self.model()

        try await ModelDownloader(installation: installation, fetcher: fetcher).download(model, from: Self.base) { _ in
        }
        for handle in fetcher.kept.withLock({ $0 }) {
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: Data("überschrieben".utf8))
        }

        let folder = installation.directory(for: model)
        #expect(try Data(contentsOf: folder.appending(path: "Encoder.mlmodelc/weights/weight.bin")) == Self.weights)
        #expect(try Data(contentsOf: folder.appending(path: "vocab.json")) == Self.vocabulary)
    }

    @Test("progress counts the model's bytes on this mac, across its files, up to its size")
    func progress() async throws {
        let temp = try TemporaryDirectory()
        let seen = Mutex<[Int64]>([])
        try await ModelDownloader(
            installation: ModelInstallation(root: temp.url), fetcher: FakeModelFetcher(files: Self.served)
        )
        .download(Self.model(), from: Self.base) { bytes in seen.withLock { $0.append(bytes) } }

        let reported = seen.withLock { $0 }
        let total = Int64(Self.weights.count + Self.vocabulary.count)
        #expect(reported.last == total)
        #expect(reported == reported.sorted())
        #expect(reported.contains(Int64(Self.weights.count + Self.vocabulary.count / 2)))
    }
}
