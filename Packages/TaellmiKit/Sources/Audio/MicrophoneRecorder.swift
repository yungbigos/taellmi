import AVFoundation
import Domain
import Foundation
import os

/// Records the default microphone with AVAudioEngine: mono AAC to a scratch file, and the same audio
/// live to whoever listens (the live preview).
public actor MicrophoneRecorder: AudioRecording {
    private let scratchFolder: URL
    private let sampleRate: Double
    private var session: Session?
    private var startedAt: Date?

    /// - Parameters:
    ///   - scratchFolder: where in-progress recordings live until they become an Entry.
    ///   - sampleRate: from the `capture.sample_rate` setting.
    public init(scratchFolder: URL, sampleRate: Double) {
        self.scratchFolder = scratchFolder
        self.sampleRate = sampleRate
    }

    public func start() async throws {
        guard session == nil else { throw CaptureError.alreadyRecording }
        guard await AVAudioApplication.requestRecordPermission() else { throw CaptureError.microphoneDenied }
        try FileManager.default.createDirectory(at: scratchFolder, withIntermediateDirectories: true)
        let file = scratchFolder.appendingPathComponent("\(UUID().uuidString).m4a")
        session = try Session(file: file, sampleRate: sampleRate)
        startedAt = Date()
    }

    public func stop() async throws -> Recording {
        guard let session, let startedAt else { throw CaptureError.notRecording }
        let duration = session.stop()
        self.session = nil
        self.startedAt = nil
        return Recording(file: session.file, durationSeconds: duration, startedAt: startedAt)
    }

    public func level() async -> Float {
        session?.level ?? 0
    }

    public func liveAudio() async -> AsyncStream<AudioSamples> {
        guard let session else { return AsyncStream { $0.finish() } }
        return session.subscribe()
    }
}

/// One running recording. The audio tap runs on a real-time thread, so all shared state lives
/// behind a lock.
// Safe: `engine` is only touched in `init` and `stop()`, which the owning actor calls one at a time;
// everything the audio thread touches is inside `state`, guarded by the lock.
private final class Session: @unchecked Sendable {
    let file: URL
    private let engine = AVAudioEngine()
    private let state: OSAllocatedUnfairLock<State>
    private let logger = Logger(subsystem: "app.taellmi", category: "audio")

    private struct State: @unchecked Sendable {
        // Safe: only touched inside `state.withLock`, never handed out.
        var output: AVAudioFile
        var converter: AVAudioConverter
        var listeners: [AsyncStream<AudioSamples>.Continuation] = []
        var framesWritten: AVAudioFramePosition = 0
        var level: Float = 0
    }

    init(file: URL, sampleRate: Double) throws {
        self.file = file
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard
            let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: monoFormat)
        else { throw CaptureError.notRecording }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let output = try AVAudioFile(
            forWriting: file, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        state = OSAllocatedUnfairLock(uncheckedState: State(output: output, converter: converter))

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer, monoFormat: monoFormat)
        }
        try engine.start()
    }

    var level: Float { state.withLock { $0.level } }

    func subscribe() -> AsyncStream<AudioSamples> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: AudioSamples.self, bufferingPolicy: .bufferingNewest(64))
        state.withLock { $0.listeners.append(continuation) }
        return stream
    }

    /// Stops capture, closes the file and ends all live streams. Returns the recorded duration in seconds.
    func stop() -> Double {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return state.withLockUnchecked { state in
            for listener in state.listeners { listener.finish() }
            state.listeners.removeAll()
            // Close explicitly: the file is only a valid .m4a once its index is written, and it is moved into
            // the Archive right after this returns. Relying on deinit lost a recording.
            state.output.close()
            return Double(state.framesWritten) / state.output.processingFormat.sampleRate
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer, monoFormat: AVAudioFormat) {
        let ratio = monoFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: capacity) else { return }
        state.withLockUnchecked { state in
            let pending = PendingInput(buffer)
            var error: NSError?
            state.converter.convert(to: mono, error: &error) { _, status in
                guard let buffer = pending.take() else {
                    status.pointee = .noDataNow
                    return nil
                }
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, mono.frameLength > 0, let channel = mono.floatChannelData?[0] else { return }
            do {
                try state.output.write(from: mono)
                state.framesWritten += AVAudioFramePosition(mono.frameLength)
            } catch {
                logger.error("Writing audio failed: \(error.localizedDescription)")
            }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(mono.frameLength)))
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            state.level = min(1, rms * 8)
            let chunk = AudioSamples(samples: samples, sampleRate: monoFormat.sampleRate)
            for listener in state.listeners { listener.yield(chunk) }
        }
    }
}

/// Hands one input buffer to AVAudioConverter's (Sendable) input block exactly once.
// Safe: created, used and dropped synchronously inside one `convert` call on the audio thread.
private final class PendingInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
