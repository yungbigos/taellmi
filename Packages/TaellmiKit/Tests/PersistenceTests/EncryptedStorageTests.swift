import CryptoKit
import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Encrypted Archive storage")
struct EncryptedStorageTests {
    private func makeStorage() throws -> (EncryptedStorage, TemporaryDirectory, TemporaryDirectory) {
        let archive = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let storage = EncryptedStorage(
            root: archive.url, key: SymmetricKey(size: .bits256), decryptedCache: scratch.url,
            systemTrash: { try FileManager.default.removeItem(at: $0) })
        return (storage, archive, scratch)
    }

    @Test("what is written reads back the same, but the file on disk is sealed")
    func writeRead() throws {
        let (storage, archive, scratch) = try makeStorage()
        let text = Data("Mein geheimer Gedanke über Marleen.".utf8)
        try storage.write(text, to: "entries/x/entry.md")
        #expect(try storage.read("entries/x/entry.md") == text)
        let raw = try Data(contentsOf: archive.url.appendingPathComponent("entries/x/entry.md"))
        #expect(ArchiveCrypto.isSealed(raw))
        #expect(raw.range(of: Data("Marleen".utf8)) == nil)
        withExtendedLifetime(scratch) {}
    }

    @Test("an imported recording is sealed in the Archive and the outside file is gone")
    func importSeals() throws {
        let (storage, archive, scratch) = try makeStorage()
        let outside = try TemporaryDirectory()
        let file = try outside.makeAudioFile()
        try storage.importFile(from: file, to: "entries/x/recording.m4a")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let raw = try Data(contentsOf: archive.url.appendingPathComponent("entries/x/recording.m4a"))
        #expect(ArchiveCrypto.isSealed(raw))
        withExtendedLifetime(scratch) {}
    }

    @Test("a readable copy for playback or transcription is decrypted outside the Archive")
    func readableCopy() throws {
        let (storage, archive, scratch) = try makeStorage()
        let outside = try TemporaryDirectory()
        try storage.importFile(from: try outside.makeAudioFile(), to: "entries/x/recording.m4a")
        let url = try storage.readableURL(for: "entries/x/recording.m4a")
        #expect(
            url.path.hasPrefix(scratch.url.standardizedFileURL.resolvingSymlinksInPath().path)
                || url.path.hasPrefix(scratch.url.path))
        #expect(!url.path.hasPrefix(archive.url.path))
        #expect(try Data(contentsOf: url) == Data("fake audio".utf8))
        storage.clearDecryptedCache()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("the whole Entry workflow works on top of it")
    func entryWorkflow() throws {
        let (storage, _, scratch) = try makeStorage()
        let outside = try TemporaryDirectory()
        let files = EntryFileStore(storage: storage, calendar: berlinCalendar)
        let entry = try files.createVoiceEntry(
            Recording(file: try outside.makeAudioFile(), durationSeconds: 5.6, startedAt: sampleDate))
        _ = try files.saveTranscript(germanTranscript, for: entry)
        let loaded = try files.loadEntry(folder: entry.folder)
        #expect(loaded.entry.text == germanTranscript.text)
        #expect(loaded.transcript == germanTranscript)
        #expect(try files.allEntryFolders() == [entry.folder])
        withExtendedLifetime(scratch) {}
    }
}
