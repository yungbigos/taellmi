import Foundation

/// A finished recording, before it becomes an entry.
public struct Recording: Sendable, Equatable {
    public var file: URL
    public var durationSeconds: Double
    public var startedAt: Date

    public init(file: URL, durationSeconds: Double, startedAt: Date) {
        self.file = file
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
    }
}

/// Microphone capture. Implemented by the Audio module; faked in tests.
public protocol AudioRecording: Sendable {
    func start() async throws
    func stop() async throws -> Recording
    /// Stops and throws the recording away.
    func cancel() async
    /// Current input level in 0...1, for UI feedback.
    func level() async -> Float
    /// Audio of the running recording as it arrives. Finishes when the recording stops.
    func liveAudio() async -> AsyncStream<AudioSamples>
}

/// What the UI needs from the journal. Implemented in the composition root.
public protocol Journal: Sendable {
    /// Stores the recording as a new entry and queues it for processing.
    func addVoiceEntry(_ recording: Recording) async throws -> Entry
    /// Stores a written note as a new typed Entry.
    func addTypedEntry(_ text: String) async throws -> Entry
    func recentEntries(limit: Int) async throws -> [Entry]
    /// Emits the newest Entries now and again whenever they change (e.g. when a Transcript arrives).
    func recentEntryUpdates(limit: Int) -> AsyncStream<[Entry]>
    /// Folder holding all entries, for "show in Finder".
    var archiveFolder: URL { get }
}

public enum CaptureError: Error, Equatable {
    case microphoneDenied
    case notRecording
    case alreadyRecording
}

/// A chunk of mono audio while recording, for live preview. Plain floats keep Domain free of AVFoundation.
public struct AudioSamples: Sendable, Equatable {
    public var samples: [Float]
    public var sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

/// What the live preview shows while you talk. Throwaway: the final Text comes from the real Transcript.
public struct LivePreview: Sendable, Equatable {
    /// Text the recogniser will not change any more.
    public var finalized: String
    /// The recogniser's current guess for the last few words.
    public var volatile: String

    public init(finalized: String = "", volatile: String = "") {
        self.finalized = finalized
        self.volatile = volatile
    }

    public var text: String {
        [finalized, volatile].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Turns live audio into a running preview. Implemented by a live-transcription engine.
public protocol LivePreviewing: Sendable {
    func preview(_ audio: AsyncStream<AudioSamples>) async throws -> AsyncThrowingStream<LivePreview, any Error>
}
