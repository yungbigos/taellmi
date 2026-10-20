import CryptoKit
import Foundation

/// Where the Archive key and Recovery Key are kept on this Mac (the Keychain in the app).
public protocol ArchiveKeyStore: Sendable {
    func loadKey() throws -> SymmetricKey?
    func saveKey(_ key: SymmetricKey) throws
    /// The Recovery Key of a fresh setup, kept only until you confirm you saved it.
    func loadPendingRecoveryKey() throws -> RecoveryKey?
    func savePendingRecoveryKey(_ key: RecoveryKey) throws
    func clearPendingRecoveryKey() throws
    /// Keeps the Recovery Key in the Keychain, if you choose to.
    func saveRecoveryKey(_ key: RecoveryKey) throws
}

/// Opens the Archive's key (ADR 0010): sets it up the first time, finds it in the Keychain later,
/// and restores it from the Recovery Key on a new Mac. It never replaces an Archive's key.
public struct ArchiveVault: Sendable {
    public enum Error: Swift.Error, Equatable {
        /// The Archive has encrypted thoughts but no archive.key (missing, or still downloading).
        case keyFileMissing
    }

    public enum State: Equatable, Sendable {
        /// Ready. `newRecoveryKey` is set until you have confirmed saving it.
        case unlocked(SymmetricKey, newRecoveryKey: RecoveryKey?)
        /// The Archive has a key, but this Mac doesn't know it (or knows a different one).
        case needsRecoveryKey

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.needsRecoveryKey, .needsRecoveryKey): true
            case (.unlocked(let a, let ra), .unlocked(let b, let rb)):
                a.withUnsafeBytes { Data($0) } == b.withUnsafeBytes { Data($0) } && ra == rb
            default: false
            }
        }
    }

    static let keyFileName = "archive.key"
    private let root: URL
    private let keyStore: any ArchiveKeyStore

    public init(root: URL, keyStore: any ArchiveKeyStore) {
        self.root = root
        self.keyStore = keyStore
    }

    private var keyFileURL: URL { root.appendingPathComponent(Self.keyFileName) }

    public func open() throws -> State {
        if FileManager.default.fileExists(atPath: keyFileURL.path) {
            let keyFile = try ArchiveKeyFile(data: Data(contentsOf: keyFileURL))
            guard let key = try keyStore.loadKey(), keyFile.matches(key) else { return .needsRecoveryKey }
            return .unlocked(key, newRecoveryKey: try keyStore.loadPendingRecoveryKey())
        }
        // Never set up a new key for an Archive that already has encrypted thoughts: that would lock them out.
        guard !keyFileIsDownloading, try !hasSealedEntries() else { throw Error.keyFileMissing }
        let stored = try keyStore.loadKey()
        let key = stored ?? SymmetricKey(size: .bits256)
        let recovery = RecoveryKey.generate()
        // Keychain first: if anything fails before archive.key exists, the next start sets up again with the
        // same key, and nothing is ever encrypted with a key this Mac doesn't hold.
        if stored == nil { try keyStore.saveKey(key) }
        try keyStore.savePendingRecoveryKey(recovery)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ArchiveKeyFile(wrapping: key, with: recovery).data().write(to: keyFileURL, options: .withoutOverwriting)
        return .unlocked(key, newRecoveryKey: recovery)
    }

    /// Unlocks the Archive on this Mac with its Recovery Key and remembers the key.
    public func unlock(with recovery: RecoveryKey) throws -> SymmetricKey {
        let key = try ArchiveKeyFile(data: Data(contentsOf: keyFileURL)).unwrap(with: recovery)
        try keyStore.saveKey(key)
        try keyStore.clearPendingRecoveryKey()
        return key
    }

    /// You typed the last group of the new Recovery Key: true if it matches, and then it stops being shown.
    public func confirmRecoveryKey(lastGroup typed: String, keepInKeychain: Bool) throws -> Bool {
        guard let pending = try keyStore.loadPendingRecoveryKey(),
            typed.uppercased().trimmingCharacters(in: .whitespaces) == pending.lastGroup
        else { return false }
        if keepInKeychain { try keyStore.saveRecoveryKey(pending) }
        try keyStore.clearPendingRecoveryKey()
        return true
    }

    private var keyFileIsDownloading: Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".\(Self.keyFileName).icloud").path)
    }

    /// Listing errors throw rather than count as "nothing sealed", so a glitch can never lead to a new key.
    private func hasSealedEntries() throws -> Bool {
        let plain = PlainFolderStorage(root: root)
        for area in ["entries", "trash/entries"] {
            for path in try plain.files(named: "entry.md", under: area) {
                if ArchiveCrypto.isSealed(try plain.read(path)) { return true }
            }
        }
        return false
    }
}

/// Encrypts an Archive that still has plain files (from before ADR 0010).
///
/// Crash-safe and repeatable:
/// - each Entry gets a target id derived from its old folder, so a rerun after a crash overwrites the same
///   copy instead of making a duplicate;
/// - entry.md is sealed last, so a half-written copy is never seen as an Entry;
/// - the plain folder is first renamed to `.migrated-…` (atomic), then removed; leftovers are swept on start;
/// - one unreadable Entry is reported and skipped, never fatal.
public enum ArchiveMigration {
    public struct Report: Sendable, Equatable {
        public var migrated = 0
        public var repaired = 0
        public var failed: [String] = []
    }

    static let retiredPrefix = ".migrated-"

    /// Whether any thought in the Archive is still a plain file.
    public static func hasPlainEntries(root: URL) -> Bool {
        let plain = PlainFolderStorage(root: root)
        for area in ["entries", "trash/entries"] {
            for path in (try? plain.files(named: "entry.md", under: area)) ?? []
            where !path.contains(retiredPrefix) {
                if let data = try? plain.read(path), !ArchiveCrypto.isSealed(data) { return true }
            }
        }
        return false
    }

    public static func encryptPlainEntries(root: URL, into encrypted: EncryptedStorage, key: SymmetricKey) throws
        -> Report
    {
        let plain = PlainFolderStorage(root: root)
        var report = Report()
        for area in ["entries", "trash/entries"] {
            sweepRetired(in: root.appendingPathComponent(area))
            for documentPath in try plain.files(named: "entry.md", under: area) {
                let folder = String(documentPath.dropLast("/entry.md".count))
                guard !folder.split(separator: "/").contains(where: { $0.hasPrefix(retiredPrefix) }) else { continue }
                do {
                    if ArchiveCrypto.isSealed(try plain.read(documentPath)) {
                        if try sealLeftovers(in: folder, root: root, plain: plain, encrypted: encrypted) {
                            report.repaired += 1
                        }
                        continue
                    }
                    try migrate(folder, area: area, root: root, plain: plain, encrypted: encrypted, key: key)
                    report.migrated += 1
                } catch {
                    report.failed.append(folder)
                }
            }
            removeEmptyFolders(in: root.appendingPathComponent(area))
        }
        if plain.exists(CurationStore.fileName), !ArchiveCrypto.isSealed(try plain.read(CurationStore.fileName)) {
            try encrypted.write(try plain.read(CurationStore.fileName), to: CurationStore.fileName)
        }
        return report
    }

    private static func migrate(
        _ folder: String, area: String, root: URL, plain: PlainFolderStorage, encrypted: EncryptedStorage,
        key: SymmetricKey
    ) throws {
        let id = targetID(for: folder, key: key)
        let target = "\(area)/\(id)"
        let names = try regularFiles(in: root.appendingPathComponent(folder)).sorted {
            $0 != "entry.md" && $1 == "entry.md"
        }
        do {
            for name in names {
                let content = try plain.read("\(folder)/\(name)")
                try encrypted.write(content, to: "\(target)/\(name)")
                guard try encrypted.read("\(target)/\(name)") == content else { throw ArchiveCrypto.Error.notSealed }
            }
        } catch {
            if target != folder { try? plain.remove(target) }
            throw error
        }
        guard target != folder else { return }
        let retired = "\(area)/\(retiredPrefix)\(id)"
        try? plain.remove(retired)
        try plain.move(folder, to: retired)
        try plain.remove(retired)
    }

    /// Seals any plain file left in a folder whose entry.md is already sealed (after a crash). True if any.
    private static func sealLeftovers(
        in folder: String, root: URL, plain: PlainFolderStorage, encrypted: EncryptedStorage
    ) throws -> Bool {
        var repaired = false
        for name in try regularFiles(in: root.appendingPathComponent(folder)) {
            let content = try plain.read("\(folder)/\(name)")
            guard !ArchiveCrypto.isSealed(content) else { continue }
            try encrypted.write(content, to: "\(folder)/\(name)")
            repaired = true
        }
        return repaired
    }

    /// A stable random-looking id for a plain folder, so reruns land on the same target.
    static func targetID(for folder: String, key: SymmetricKey) -> String {
        let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")
        let mac = Array(HMAC<SHA256>.authenticationCode(for: Data(folder.utf8), using: key))
        return String(mac.prefix(16).map { alphabet[Int($0) % 32] })
    }

    private static func regularFiles(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.lastPathComponent)
    }

    private static func sweepRetired(in area: URL) {
        let children = (try? FileManager.default.contentsOfDirectory(atPath: area.path)) ?? []
        for name in children where name.hasPrefix(retiredPrefix) {
            try? FileManager.default.removeItem(at: area.appendingPathComponent(name))
        }
    }

    /// Old dated folders (entries/2026/10/…) are left empty after the move.
    private static func removeEmptyFolders(in folder: URL) {
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        else { return }
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            removeEmptyFolders(in: child)
            if (try? FileManager.default.contentsOfDirectory(atPath: child.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: child)
            }
        }
    }
}
