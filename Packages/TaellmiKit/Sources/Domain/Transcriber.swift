import Foundation

/// What an engine hands back: plain text plus timed tokens. The pipeline turns it into a `Transcript`.
public struct RawTranscription: Sendable, Equatable {
    public var text: String
    public var tokens: [TimedToken]
    public var durationSeconds: Double

    public init(text: String, tokens: [TimedToken], durationSeconds: Double) {
        self.text = text
        self.tokens = tokens
        self.durationSeconds = durationSeconds
    }
}

/// Turns a finished recording into verbatim text. Implemented by engine adapters.
public protocol Transcriber: Sendable {
    func transcribe(audioFile: URL) async throws -> RawTranscription
    /// Releases model memory. The next `transcribe` call loads the model again.
    func unload() async
}
