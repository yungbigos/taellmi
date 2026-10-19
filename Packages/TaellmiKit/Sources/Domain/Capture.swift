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
    /// Current input level in 0...1, for UI feedback.
    func level() async -> Float
}

/// What the UI needs from the journal. Implemented in the composition root.
public protocol Journal: Sendable {
    /// Stores the recording as a new entry and queues it for processing.
    func addVoiceEntry(_ recording: Recording) async throws -> Entry
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
