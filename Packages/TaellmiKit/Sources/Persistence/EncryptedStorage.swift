import CryptoKit
import Foundation

/// The Archive with every file sealed by the Archive key (ADR 0010). File and folder names stay
/// plain, which is safe because they carry no meaning (random Entry ids, fixed file names).
public struct EncryptedStorage: ArchiveStorage {
    private let files: PlainFolderStorage
    private let key: SymmetricKey
    /// Where decrypted copies for playback and transcription go: the app's protected scratch area,
    /// never the Archive. Cleared on start.
    private let decryptedCache: URL

    public init(
        root: URL, key: SymmetricKey, decryptedCache: URL,
        systemTrash: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        files = PlainFolderStorage(root: root, systemTrash: systemTrash)
        self.key = key
        self.decryptedCache = decryptedCache
    }

    public func read(_ path: String) throws -> Data {
        try ArchiveCrypto.open(files.read(path), with: key)
    }

    public func write(_ data: Data, to path: String) throws {
        try files.write(ArchiveCrypto.seal(data, with: key), to: path)
    }

    public func exists(_ path: String) -> Bool { files.exists(path) }
    public func remove(_ path: String) throws { try files.remove(path) }
    public func moveToSystemTrash(_ path: String) throws { try files.moveToSystemTrash(path) }
    public func move(_ path: String, to destination: String) throws { try files.move(path, to: destination) }

    public func files(named name: String, under folder: String) throws -> [String] {
        try files.files(named: name, under: folder)
    }

    public func importFile(from url: URL, to path: String) throws {
        try write(Data(contentsOf: url), to: path)
        try FileManager.default.removeItem(at: url)
    }

    /// A decrypted copy in the app's scratch area. One copy per Archive file, reused, so copies don't pile up;
    /// the whole cache is cleared on start.
    public func readableURL(for path: String) throws -> URL {
        try FileManager.default.createDirectory(at: decryptedCache, withIntermediateDirectories: true)
        let name = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        let copy = decryptedCache.appendingPathComponent(String(name))
            .appendingPathExtension((path as NSString).pathExtension)
        if !FileManager.default.fileExists(atPath: copy.path) {
            try read(path).write(to: copy, options: .atomic)
        }
        return copy
    }

    /// Removes all decrypted copies.
    public func clearDecryptedCache() {
        try? FileManager.default.removeItem(at: decryptedCache)
    }
}
