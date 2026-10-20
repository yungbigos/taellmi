import AVFoundation
import Config
import CryptoKit
import Domain
import Foundation
import Persistence
import Pipeline
import os

/// Everything the app does at launch before it is ready, run off the main actor.
nonisolated struct StartupWork: Sendable {
    let paths: AppPaths
    let database: AppDatabase
    let files: EntryFileStore
    let index: EntryIndex
    let runner: PipelineRunner
    let storage: any ArchiveStorage
    let archiveRoot: URL
    let archiveKey: SymmetricKey?
    private let logger = Logger(subsystem: "app.taellmi", category: "startup")

    init(
        paths: AppPaths, database: AppDatabase, files: EntryFileStore, index: EntryIndex, runner: PipelineRunner,
        storage: any ArchiveStorage, archiveRoot: URL, archiveKey: SymmetricKey?
    ) {
        self.archiveKey = archiveKey
        self.storage = storage
        self.archiveRoot = archiveRoot
        self.paths = paths
        self.database = database
        self.files = files
        self.index = index
        self.runner = runner
    }

    /// Before the first encryption: a copy of the plain Archive inside the app's protected folder, in case
    /// anything goes wrong. Made once.
    private func backUpPlainArchive() throws {
        let backup = paths.root.appendingPathComponent("Archive backup before encryption", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try FileManager.default.copyItem(at: archiveRoot, to: backup)
        logger.notice("Backed up the plain Archive before encrypting it")
    }

    /// Returns how many thoughts could not be encrypted.
    @discardableResult
    func run() async throws -> Int {
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        var failures = 0
        if let encrypted = storage as? EncryptedStorage, let key = archiveKey {
            encrypted.clearDecryptedCache()
            if ArchiveMigration.hasPlainEntries(root: archiveRoot) { try backUpPlainArchive() }
            let report = try ArchiveMigration.encryptPlainEntries(root: archiveRoot, into: encrypted, key: key)
            failures = report.failed.count
            logger.notice(
                "Archive encryption: \(report.migrated) migrated, \(report.repaired) repaired, \(report.failed.count) failed"
            )
        }
        let seeded = try Seeder(database: database).apply(SeedBundle.bundled())
        logger.info("Config seeded: \(seeded.inserted) new, \(seeded.updated) updated")
        try recoverScratchRecordings()
        let report = try index.rebuild(from: files)
        logger.info("Index rebuilt: \(report.indexed) entries, \(report.invalidFolders.count) unreadable")
        try await runner.recoverInterrupted()
        for entry in try index.awaitingTranscription() where files.hasRecording(entry) {
            try await runner.enqueue(entry)
        }
        return failures
    }

    /// Recordings still in the scratch folder were interrupted (crash, quit) before becoming an Entry.
    private func recoverScratchRecordings() throws {
        guard
            let leftovers = try? FileManager.default.contentsOfDirectory(
                at: paths.scratch, includingPropertiesForKeys: [.creationDateKey])
        else { return }
        for file in leftovers where file.pathExtension == "m4a" {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let entry = try files.createVoiceEntry(
                Recording(file: file, durationSeconds: Self.duration(of: file), startedAt: created))
            logger.info("Recovered an interrupted recording as Entry \(entry.id)")
        }
    }

    private static func duration(of file: URL) -> Double {
        guard let audio = try? AVAudioFile(forReading: file), audio.fileFormat.sampleRate > 0 else { return 0 }
        return Double(audio.length) / audio.fileFormat.sampleRate
    }
}
