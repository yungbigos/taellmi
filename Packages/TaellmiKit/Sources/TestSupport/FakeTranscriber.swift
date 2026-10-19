import Domain
import Foundation

/// A transcriber that returns a canned result and records how it was used.
public actor FakeTranscriber: Transcriber {
    public struct Failure: Error, Equatable {
        public init() {}
    }

    public private(set) var transcribeCalls: [URL] = []
    public private(set) var unloadCalls = 0
    private var result: RawTranscription
    private var failuresRemaining: Int

    public init(result: RawTranscription = FakeTranscriber.germanResult, failTimes: Int = 0) {
        self.result = result
        self.failuresRemaining = failTimes
    }

    public func transcribe(audioFile: URL) async throws -> RawTranscription {
        transcribeCalls.append(audioFile)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Failure()
        }
        return result
    }

    public func unload() async {
        unloadCalls += 1
    }

    public static let germanResult = RawTranscription(
        text: "Ich war heute im Büro. Honestly, ziemlich anstrengend.",
        tokens: [
            TimedToken(text: "▁Ich", start: 0.0, end: 0.2), TimedToken(text: "▁war", start: 0.2, end: 0.4),
            TimedToken(text: "▁heute", start: 0.4, end: 0.7), TimedToken(text: "▁im", start: 0.7, end: 0.8),
            TimedToken(text: "▁Büro", start: 0.8, end: 1.1), TimedToken(text: ".", start: 1.1, end: 1.15),
            TimedToken(text: "▁Honestly", start: 1.6, end: 2.0), TimedToken(text: ",", start: 2.0, end: 2.05),
            TimedToken(text: "▁ziemlich", start: 2.1, end: 2.5), TimedToken(text: "▁anstrengend", start: 2.5, end: 3.1),
            TimedToken(text: ".", start: 3.1, end: 3.15),
        ],
        durationSeconds: 3.4)
}
