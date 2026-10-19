import AVFoundation
import Domain
import Foundation
import Speech
import SpeechAnalyzerEngine
import Testing

/// Runs Apple's on-device recogniser on a German clip, fed in small chunks like the microphone does.
/// Needs the German speech assets installed by macOS; skipped by the fast gate.
@Suite("Apple live preview on real audio", .enabled { await AppleSpeechFixture.germanInstalled() })
struct AppleSpeechLivePreviewIntegrationTests {
    @Test("hears German speech fed in live chunks")
    func previewsGerman() async throws {
        let preview = AppleSpeechLivePreview(
            options: try AppleSpeechOptions(params: ["locale": .string("de-DE")]), vocabulary: ["Marleen"])
        let (audio, feed) = AsyncStream.makeStream(of: AudioSamples.self)
        let updates = try await preview.preview(audio)
        for chunk in try AppleSpeechFixture.chunks() { feed.yield(chunk) }
        feed.finish()

        var last = LivePreview()
        for try await update in updates { last = update }

        #expect(last.text.lowercased().contains("wetter"), "got: \(last.text)")
    }
}

enum AppleSpeechFixture {
    static func germanInstalled() async -> Bool {
        await SpeechTranscriber.installedLocales.contains { $0.identifier.hasPrefix("de") }
    }

    /// The fixture as 0.1 s mono float chunks.
    static func chunks() throws -> [AudioSamples] {
        guard let url = Bundle.module.url(forResource: "Fixtures/heute-wetter-de", withExtension: "m4a") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let size = AVAudioFrameCount(format.sampleRate / 10)
        var chunks: [AudioSamples] = []
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: size) else { break }
            try file.read(into: buffer, frameCount: size)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            chunks.append(
                AudioSamples(
                    samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
                    sampleRate: format.sampleRate))
        }
        return chunks
    }
}
