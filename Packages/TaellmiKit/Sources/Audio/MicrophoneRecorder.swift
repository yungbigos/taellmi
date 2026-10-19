import AVFoundation
import Domain
import Foundation

/// Records the default microphone to a mono AAC file in a scratch folder.
public actor MicrophoneRecorder: AudioRecording {
    private let scratchFolder: URL
    private let sampleRate: Double
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    /// - Parameters:
    ///   - scratchFolder: where in-progress recordings live until they become an Entry.
    ///   - sampleRate: from the `capture.sample_rate` setting.
    public init(scratchFolder: URL, sampleRate: Double) {
        self.scratchFolder = scratchFolder
        self.sampleRate = sampleRate
    }

    public func start() async throws {
        guard recorder == nil else { throw CaptureError.alreadyRecording }
        guard await AVAudioApplication.requestRecordPermission() else { throw CaptureError.microphoneDenied }

        try FileManager.default.createDirectory(at: scratchFolder, withIntermediateDirectories: true)
        let file = scratchFolder.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: file, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw CaptureError.notRecording }
        self.recorder = recorder
        startedAt = Date()
    }

    public func stop() async throws -> Recording {
        guard let recorder, let startedAt else { throw CaptureError.notRecording }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.startedAt = nil
        return Recording(file: recorder.url, durationSeconds: duration, startedAt: startedAt)
    }

    public func level() async -> Float {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        // averagePower is in dBFS (-160...0); map the useful -50...0 range to 0...1.
        return max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
    }
}
