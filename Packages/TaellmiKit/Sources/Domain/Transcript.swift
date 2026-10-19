import Foundation

/// One token with timing, as produced by a speech-to-text engine.
public struct TimedToken: Sendable, Equatable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A sentence- or pause-delimited stretch of speech with its position in the audio.
public struct TranscriptSegment: Sendable, Equatable, Codable {
    public var startMs: Int
    public var endMs: Int
    public var text: String

    public init(startMs: Int, endMs: Int, text: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
    }
}

/// The verbatim result of transcribing one recording.
public struct Transcript: Sendable, Equatable, Codable {
    public var text: String
    public var segments: [TranscriptSegment]
    /// The `model.id` from config that produced this transcript.
    public var modelID: String
    public var durationSeconds: Double

    public init(text: String, segments: [TranscriptSegment], modelID: String, durationSeconds: Double) {
        self.text = text
        self.segments = segments
        self.modelID = modelID
        self.durationSeconds = durationSeconds
    }
}
