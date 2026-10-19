import Domain
import Foundation
import GRDB
import Persistence

/// A fresh in-memory database with the real migrations applied.
public func makeDatabase() throws -> AppDatabase {
    try AppDatabase(DatabaseQueue())
}

/// A temporary folder that is removed when the value is deinitialised.
public final class TemporaryDirectory: Sendable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("taellmi-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a small dummy audio file and returns its URL.
    public func makeAudioFile(named name: String = "recording.m4a") throws -> URL {
        let file = url.appendingPathComponent(name)
        try Data("fake audio".utf8).write(to: file)
        return file
    }
}

/// A fixed calendar in Europe/Berlin so folder names are deterministic.
public let berlinCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
}()

/// 2026-10-19 20:34:12 in Berlin.
public let sampleDate = Date(timeIntervalSince1970: 1_792_434_852)

public let germanTranscript = Transcript(
    text: "Ich hatte heute ein komisches Gefühl wegen der Zukunftsangst. Honestly, kind of weird.",
    segments: [
        TranscriptSegment(
            startMs: 0, endMs: 3400, text: "Ich hatte heute ein komisches Gefühl wegen der Zukunftsangst."),
        TranscriptSegment(startMs: 3900, endMs: 5600, text: "Honestly, kind of weird."),
    ],
    modelID: "fake-transcriber",
    durationSeconds: 5.6
)
