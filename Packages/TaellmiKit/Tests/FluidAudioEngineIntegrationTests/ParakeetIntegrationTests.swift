import Domain
import FluidAudioEngine
import Foundation
import Testing

/// Runs the real Parakeet model on a short German clip. Needs the model downloaded
/// (scripts/download-model.sh) and is skipped by the fast gate.
@Suite("Parakeet on real audio", .enabled(if: ParakeetFixture.isAvailable))
struct ParakeetIntegrationTests {
    @Test("transcribes German speech with timed tokens")
    func transcribesGerman() async throws {
        let transcriber = try ParakeetTranscriber(
            options: ParakeetOptions(params: ["version": .string("v3"), "encoder_precision": .string("int8-v2")]),
            directory: ParakeetFixture.modelDirectory)
        let result = try await transcriber.transcribe(audioFile: try ParakeetFixture.germanClip())
        await transcriber.unload()

        let words = Set(result.text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let expected: Set<String> = ["heute", "wetter", "schön"]
        #expect(expected.isSubset(of: words), "got: \(result.text)")
        #expect(!result.tokens.isEmpty)
        #expect(result.tokens == result.tokens.sorted { $0.start <= $1.start })
    }
}

enum ParakeetFixture {
    /// Defaults to the sandboxed app's model folder; override with TAELLMI_MODELS_DIR.
    static var modelDirectory: URL {
        let root =
            ProcessInfo.processInfo.environment["TAELLMI_MODELS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/app.taellmi/Data/Library/Application Support/taellmi/models")
        return root.appendingPathComponent("parakeet-tdt-0.6b-v3")
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent(".taellmi-verified").path)
    }

    static func germanClip() throws -> URL {
        guard let url = Bundle.module.url(forResource: "Fixtures/heute-wetter-de", withExtension: "m4a") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
