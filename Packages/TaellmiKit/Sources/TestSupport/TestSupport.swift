import AVFoundation
import Config
import Domain
import Foundation
import GRDB
import Persistence

/// A fresh in-memory database with the real migrations applied.
public func makeDatabase() throws -> AppDatabase {
    try AppDatabase(DatabaseQueue(configuration: AppDatabase.configuration()))
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

    /// A real, readable m4a of silence lasting `seconds`.
    public func makeRealAudioFile(named name: String = "real.m4a", seconds: Double) throws -> URL {
        let file = url.appendingPathComponent(name)
        let rate = 16_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * seconds))
        else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = buffer.frameCapacity
        let audio = try AVAudioFile(
            forWriting: file,
            settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1])
        try audio.write(from: buffer)
        audio.close()
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

/// A fresh in-memory database with the real migrations and the bundled default config.
public func makeSeededDatabase() throws -> AppDatabase {
    let database = try makeDatabase()
    _ = try Seeder(database: database).apply(SeedBundle.bundled())
    return database
}
