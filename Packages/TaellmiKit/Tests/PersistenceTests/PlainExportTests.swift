import CryptoKit
import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Export as plain files")
struct PlainExportTests {
    @Test("every thought becomes a readable folder named by its date, with Text, recording and transcript")
    func exports() throws {
        let archive = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let target = try TemporaryDirectory()
        let encrypted = EncryptedStorage(
            root: archive.url, key: SymmetricKey(size: .bits256), decryptedCache: scratch.url)
        let files = EntryFileStore(storage: encrypted, calendar: berlinCalendar)
        let spoken = try files.saveTranscript(
            germanTranscript,
            for: try files.createVoiceEntry(
                Recording(file: try outside.makeAudioFile(), durationSeconds: 5.6, startedAt: sampleDate)))
        _ = try files.createTypedEntry(text: "Getippt.", createdAt: sampleDate.addingTimeInterval(60))

        let count = try PlainExport.export(files, to: target.url, calendar: berlinCalendar)

        #expect(count == 2)
        let folders = try FileManager.default.contentsOfDirectory(atPath: target.url.path).sorted()
        #expect(folders.count == 2)
        #expect(folders.first?.hasPrefix("2026-10-19 20.34") == true)
        let spokenFolder = target.url.appendingPathComponent(try #require(folders.first))
        let markdown = try String(contentsOf: spokenFolder.appendingPathComponent("entry.md"), encoding: .utf8)
        #expect(markdown.contains(spoken.text))
        #expect(try Data(contentsOf: spokenFolder.appendingPathComponent("recording.m4a")) == Data("fake audio".utf8))
        #expect(FileManager.default.fileExists(atPath: spokenFolder.appendingPathComponent("transcript.json").path))
    }
}
