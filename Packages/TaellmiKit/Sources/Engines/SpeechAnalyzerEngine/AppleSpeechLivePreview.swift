import AVFoundation
import Domain
import Foundation
import Speech

/// Engine options from a model's `params` in config.
public struct AppleSpeechOptions: Sendable {
    public enum Error: Swift.Error, Equatable {
        case missingParam(String)
        case unsupportedLocale(String)
    }

    public let localeIdentifier: String

    public init(params: [String: JSONValue]) throws {
        guard let locale = params["locale"]?.stringValue else { throw Error.missingParam("locale") }
        localeIdentifier = locale
    }
}

/// Live preview with Apple's on-device SpeechTranscriber (macOS 26). The speech model is managed by
/// macOS; if the language is missing, macOS downloads it, not this app.
public struct AppleSpeechLivePreview: LivePreviewing {
    public static let engineKey = "apple_speech"
    public static let factory: LivePreviewFactory = { model, vocabulary in
        try AppleSpeechLivePreview(options: AppleSpeechOptions(params: model.params), vocabulary: vocabulary)
    }

    private let options: AppleSpeechOptions
    private let vocabulary: [String]

    public init(options: AppleSpeechOptions, vocabulary: [String]) {
        self.options = options
        self.vocabulary = vocabulary
    }

    public func preview(_ audio: AsyncStream<AudioSamples>) async throws -> AsyncThrowingStream<LivePreview, any Error>
    {
        guard
            let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: options.localeIdentifier))
        else { throw AppleSpeechOptions.Error.unsupportedLocale(options.localeIdentifier) }

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let context = AnalysisContext()
        context.contextualStrings = [.general: vocabulary]
        try await analyzer.setContext(context)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechOptions.Error.unsupportedLocale(options.localeIdentifier)
        }

        let (input, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let feeder = Task {
            let converter = SampleConverter(target: format)
            for await chunk in audio {
                if let buffer = converter.buffer(from: chunk) { inputContinuation.yield(AnalyzerInput(buffer: buffer)) }
            }
            inputContinuation.finish()
        }
        try await analyzer.start(inputSequence: input)

        return AsyncThrowingStream { continuation in
            let reader = Task {
                var preview = LivePreview()
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespaces)
                        if result.isFinal {
                            preview.finalized = [preview.finalized, text].filter { !$0.isEmpty }.joined(separator: " ")
                            preview.volatile = ""
                        } else {
                            preview.volatile = text
                        }
                        continuation.yield(preview)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let finisher = Task {
                await feeder.value
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            continuation.onTermination = { _ in
                feeder.cancel()
                finisher.cancel()
                reader.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        }
    }
}

/// Converts plain mono float chunks into PCM buffers in the format the analyzer wants.
private final class SampleConverter {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceRate: Double = 0

    init(target: AVAudioFormat) {
        self.target = target
    }

    func buffer(from chunk: AudioSamples) -> AVAudioPCMBuffer? {
        guard
            let source = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: chunk.sampleRate, channels: 1, interleaved: false),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(chunk.samples.count))
        else { return nil }
        input.frameLength = AVAudioFrameCount(chunk.samples.count)
        chunk.samples.withUnsafeBufferPointer { samples in
            input.floatChannelData?[0].update(from: samples.baseAddress!, count: samples.count)
        }
        if converter == nil || sourceRate != chunk.sampleRate {
            converter = AVAudioConverter(from: source, to: target)
            sourceRate = chunk.sampleRate
        }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * target.sampleRate / chunk.sampleRate) + 32
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }
        let pending = OneShot(input)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard let buffer = pending.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}

/// Hands one buffer to AVAudioConverter's (Sendable) input block exactly once.
// Safe: created, used and dropped synchronously inside one `convert` call.
private final class OneShot: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
