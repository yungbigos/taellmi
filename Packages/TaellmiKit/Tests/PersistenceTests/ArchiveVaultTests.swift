import CryptoKit
import Domain
import Foundation
import Persistence
import TestSupport
import Testing

private func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

@Suite("The Archive key: setup, recovery and confirmation")
struct ArchiveVaultTests {
    @Test("the first start creates a key, a Recovery Key to show, and archive.key in the Archive")
    func setup() throws {
        let archive = try TemporaryDirectory()
        let store = InMemoryKeyStore()
        guard case .unlocked(let key, let recovery?) = try ArchiveVault(root: archive.url, keyStore: store).open()
        else {
            Issue.record("expected unlocked with a new Recovery Key")
            return
        }
        #expect(FileManager.default.fileExists(atPath: archive.url.appendingPathComponent("archive.key").path))
        #expect(try store.loadKey().map(bytes) == bytes(key))
        #expect(
            try ArchiveKeyFile(data: Data(contentsOf: archive.url.appendingPathComponent("archive.key")))
                .unwrap(with: recovery).withUnsafeBytes { Data($0) } == bytes(key))
    }

    @Test("later starts use the same key and keep showing the Recovery Key until it is confirmed")
    func laterStarts() throws {
        let archive = try TemporaryDirectory()
        let store = InMemoryKeyStore()
        let vault = ArchiveVault(root: archive.url, keyStore: store)
        guard case .unlocked(let first, let recovery?) = try vault.open() else {
            Issue.record("setup")
            return
        }
        guard case .unlocked(let second, let stillPending) = try vault.open() else {
            Issue.record("open")
            return
        }
        #expect(bytes(first) == bytes(second))
        #expect(stillPending == recovery)

        #expect(try vault.confirmRecoveryKey(lastGroup: "XXXXX", keepInKeychain: false) == false)
        #expect(try vault.confirmRecoveryKey(lastGroup: recovery.lastGroup.lowercased(), keepInKeychain: true))
        guard case .unlocked(_, let afterConfirm) = try vault.open() else {
            Issue.record("open")
            return
        }
        #expect(afterConfirm == nil)
        #expect(store.savedRecoveryKey == recovery.formatted)
    }

    @Test("on a new Mac the Archive asks for the Recovery Key, and only the right one unlocks it")
    func newMac() throws {
        let archive = try TemporaryDirectory()
        guard
            case .unlocked(let key, let recovery?) = try ArchiveVault(
                root: archive.url, keyStore: InMemoryKeyStore()
            ).open()
        else {
            Issue.record("setup")
            return
        }

        let newMac = InMemoryKeyStore()
        let vault = ArchiveVault(root: archive.url, keyStore: newMac)
        #expect(try vault.open() == .needsRecoveryKey)
        #expect(throws: (any Error).self) { try vault.unlock(with: RecoveryKey.generate()) }
        #expect(bytes(try vault.unlock(with: recovery)) == bytes(key))
        guard case .unlocked(let reopened, nil) = try vault.open() else {
            Issue.record("reopen")
            return
        }
        #expect(bytes(reopened) == bytes(key))
    }
}

@Suite("Guarding against lockout")
struct ArchiveLockoutTests {
    @Test("a missing archive.key next to encrypted thoughts never creates a new key")
    func missingKeyFile() throws {
        let archive = try TemporaryDirectory()
        let store = InMemoryKeyStore()
        guard case .unlocked = try ArchiveVault(root: archive.url, keyStore: store).open() else {
            Issue.record("setup")
            return
        }
        let sealed = try ArchiveCrypto.seal(Data("x".utf8), with: SymmetricKey(size: .bits256))
        try PlainFolderStorage(root: archive.url).write(sealed, to: "entries/abc/entry.md")
        try FileManager.default.removeItem(at: archive.url.appendingPathComponent("archive.key"))

        #expect(throws: ArchiveVault.Error.keyFileMissing) {
            try ArchiveVault(root: archive.url, keyStore: store).open()
        }
        #expect(!FileManager.default.fileExists(atPath: archive.url.appendingPathComponent("archive.key").path))
    }

    @Test("an archive.key still downloading from iCloud is not replaced")
    func iCloudPlaceholder() throws {
        let archive = try TemporaryDirectory()
        try Data().write(to: archive.url.appendingPathComponent(".archive.key.icloud"))
        #expect(throws: ArchiveVault.Error.keyFileMissing) {
            try ArchiveVault(root: archive.url, keyStore: InMemoryKeyStore()).open()
        }
    }

    @Test("a Keychain key that doesn't belong to this Archive asks for the Recovery Key instead")
    func wrongKeychainKey() throws {
        let archive = try TemporaryDirectory()
        guard case .unlocked = try ArchiveVault(root: archive.url, keyStore: InMemoryKeyStore()).open() else {
            Issue.record("setup")
            return
        }
        let otherMac = InMemoryKeyStore()
        try otherMac.saveKey(SymmetricKey(size: .bits256))
        #expect(try ArchiveVault(root: archive.url, keyStore: otherMac).open() == .needsRecoveryKey)
    }
}

@Suite("Encrypting an existing plain Archive")
struct ArchiveMigrationTests {
    @Test("plain thoughts, recordings and Curation become sealed under random names; the plain originals go")
    func migrates() throws {
        let archive = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        // An Archive in the old, plain layout with dated folders.
        let plainFiles = EntryFileStore(storage: PlainFolderStorage(root: archive.url), calendar: berlinCalendar)
        let old = try plainFiles.createVoiceEntry(
            Recording(file: try outside.makeAudioFile(), durationSeconds: 5.6, startedAt: sampleDate),
            id: "20261019-203412-a1b2")
        try PlainFolderStorage(root: archive.url).move(old.folder, to: "entries/2026/10/20261019-203412-a1b2")
        let movedOld = try plainFiles.loadEntry(folder: "entries/2026/10/20261019-203412-a1b2").entry
        _ = try plainFiles.saveTranscript(germanTranscript, for: movedOld)
        try CurationStore(storage: PlainFolderStorage(root: archive.url)).addToVocabulary("Kim")

        let key = SymmetricKey(size: .bits256)
        let encrypted = EncryptedStorage(root: archive.url, key: key, decryptedCache: scratch.url)
        let migrated = try ArchiveMigration.encryptPlainEntries(root: archive.url, into: encrypted, key: key)

        #expect(migrated.migrated == 1)
        let files = EntryFileStore(storage: encrypted, calendar: berlinCalendar)
        let folders = try files.allEntryFolders()
        #expect(folders.count == 1)
        #expect(folders.first?.hasPrefix("entries/") == true && folders.first?.contains("2026") == false)
        let loaded = try files.loadEntry(folder: try #require(folders.first))
        #expect(loaded.entry.text == germanTranscript.text)
        #expect(loaded.entry.createdAt == movedOld.createdAt)
        #expect(loaded.transcript == germanTranscript)
        #expect(try CurationStore(storage: encrypted).vocabulary().map(\.text) == ["Kim"])
        #expect(!FileManager.default.fileExists(atPath: archive.url.appendingPathComponent("entries/2026").path))
        #expect(try ArchiveMigration.encryptPlainEntries(root: archive.url, into: encrypted, key: key).migrated == 0)
    }

    private func plainArchive() throws -> (TemporaryDirectory, EntryFileStore, Entry) {
        let archive = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let files = EntryFileStore(storage: PlainFolderStorage(root: archive.url), calendar: berlinCalendar)
        let entry = try files.saveTranscript(
            germanTranscript,
            for: try files.createVoiceEntry(
                Recording(file: try outside.makeAudioFile(), durationSeconds: 5.6, startedAt: sampleDate),
                id: "20261019-203412-a1b2"))
        return (archive, files, entry)
    }

    @Test("a crash after sealing but before the plain folder is removed does not create a duplicate")
    func crashBetweenSealAndRemove() throws {
        let (archive, _, entry) = try plainArchive()
        let scratch = try TemporaryDirectory()
        let key = SymmetricKey(size: .bits256)
        let encrypted = EncryptedStorage(root: archive.url, key: key, decryptedCache: scratch.url)
        // Simulate the crash: copy the plain folder aside, migrate, then put the plain folder back.
        let backup = try TemporaryDirectory()
        try FileManager.default.copyItem(
            at: archive.url.appendingPathComponent(entry.folder), to: backup.url.appendingPathComponent("copy"))
        _ = try ArchiveMigration.encryptPlainEntries(root: archive.url, into: encrypted, key: key)
        try FileManager.default.copyItem(
            at: backup.url.appendingPathComponent("copy"), to: archive.url.appendingPathComponent(entry.folder))

        _ = try ArchiveMigration.encryptPlainEntries(root: archive.url, into: encrypted, key: key)

        #expect(try EntryFileStore(storage: encrypted).allEntryFolders().count == 1)
    }

    @Test("one unreadable thought is reported and skipped; the rest migrates and nothing half-made stays")
    func partialFailure() throws {
        let (archive, files, _) = try plainArchive()
        let scratch = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let broken = try files.createVoiceEntry(
            Recording(file: try outside.makeAudioFile(), durationSeconds: 1, startedAt: sampleDate), id: "broken")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: archive.url.appendingPathComponent("\(broken.folder)/recording.m4a").path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: archive.url.appendingPathComponent("\(broken.folder)/recording.m4a").path)
        }
        let key = SymmetricKey(size: .bits256)
        let encrypted = EncryptedStorage(root: archive.url, key: key, decryptedCache: scratch.url)

        let report = try ArchiveMigration.encryptPlainEntries(root: archive.url, into: encrypted, key: key)

        #expect(report.migrated == 1)
        #expect(report.failed == [broken.folder])
        let sealedFolders = try EntryFileStore(storage: encrypted).allEntryFolders()
            .filter { (try? encrypted.read("\($0)/entry.md")) != nil }
        #expect(sealedFolders.count == 1, "no half-made sealed copy of the broken thought")
    }

    @Test("a folder with a sealed entry.md but a plain transcript is repaired")
    func mixedFolder() throws {
        let (archive, _, entry) = try plainArchive()
        let scratch = try TemporaryDirectory()
        let key = SymmetricKey(size: .bits256)
        let encrypted = EncryptedStorage(root: archive.url, key: key, decryptedCache: scratch.url)
        let plain = PlainFolderStorage(root: archive.url)
        try encrypted.write(try plain.read("\(entry.folder)/entry.md"), to: "\(entry.folder)/entry.md")

        _ = try ArchiveMigration.encryptPlainEntries(root: archive.url, into: encrypted, key: key)

        let raw = try Data(contentsOf: archive.url.appendingPathComponent("\(entry.folder)/transcript.json"))
        #expect(ArchiveCrypto.isSealed(raw))
        #expect(try EntryFileStore(storage: encrypted).loadEntry(folder: entry.folder).transcript == germanTranscript)
    }

    @Test("thoughts in the Trash are migrated too")
    func trashMigrates() throws {
        let (archive, files, entry) = try plainArchive()
        let scratch = try TemporaryDirectory()
        _ = try files.moveToTrash(entry)
        let key = SymmetricKey(size: .bits256)
        let encrypted = EncryptedStorage(root: archive.url, key: key, decryptedCache: scratch.url)
        _ = try ArchiveMigration.encryptPlainEntries(root: archive.url, into: encrypted, key: key)
        let trashed = try EntryFileStore(storage: encrypted).trashedFolders()
        #expect(trashed.count == 1)
        #expect(
            try EntryFileStore(storage: encrypted).loadEntry(folder: try #require(trashed.first)).entry.text
                == germanTranscript.text)
    }
}
