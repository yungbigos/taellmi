import CryptoKit
import Foundation
import Persistence
import Synchronization

/// Builds an encrypted demo Archive from JSON Lines files of test thoughts (`{"date", "text"}` per line), for
/// the separate demo app. Never point it at your real Archive.
///
///     swift run DemoArchiveTool <output-folder> <thoughts.jsonl>...
///
/// Prints the demo Recovery Key; the demo app asks for it after adopting the folder.
final class MemoryKeyStore: ArchiveKeyStore {
    private let state = Mutex<(key: Data?, pending: String?)>((nil, nil))
    func loadKey() throws -> SymmetricKey? { state.withLock { $0.key.map(SymmetricKey.init(data:)) } }
    func saveKey(_ key: SymmetricKey) throws { state.withLock { $0.key = key.withUnsafeBytes { Data($0) } } }
    func loadPendingRecoveryKey() throws -> RecoveryKey? {
        try state.withLock { $0.pending }.map { try RecoveryKey(parsing: $0) }
    }
    func savePendingRecoveryKey(_ key: RecoveryKey) throws { state.withLock { $0.pending = key.formatted } }
    func clearPendingRecoveryKey() throws { state.withLock { $0.pending = nil } }
    func saveRecoveryKey(_ key: RecoveryKey) throws {}
}

struct Thought: Decodable {
    let date: String
    let text: String
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2, let output = arguments.first else {
    FileHandle.standardError.write(Data("usage: DemoArchiveTool <output-folder> <thoughts.jsonl>...\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: output).appendingPathComponent("tällmi", isDirectory: true)
guard !FileManager.default.fileExists(atPath: root.path) else {
    FileHandle.standardError.write(Data("\(root.path) already exists; remove it first\n".utf8))
    exit(1)
}

let keyStore = MemoryKeyStore()
guard case .unlocked(let key, let recovery?) = try ArchiveVault(root: root, keyStore: keyStore).open() else {
    fatalError("a new Archive always unlocks with a new Recovery Key")
}
let cache = FileManager.default.temporaryDirectory.appendingPathComponent("taellmi-demo-cache-\(UUID())")
let files = EntryFileStore(storage: EncryptedStorage(root: root, key: key, decryptedCache: cache))

/// Local date and time, with or without seconds.
func parseDate(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: text) { return date }
    }
    return nil
}

var count = 0
for path in arguments.dropFirst() {
    let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
    for line in lines where !line.isEmpty {
        let thought = try JSONDecoder().decode(Thought.self, from: Data(line.utf8))
        guard let date = parseDate(thought.date) else {
            FileHandle.standardError.write(Data("unreadable date \(thought.date) in \(path)\n".utf8))
            exit(1)
        }
        _ = try files.createTypedEntry(text: thought.text, createdAt: date)
        count += 1
    }
}
try? FileManager.default.removeItem(at: cache)
print("\(count) thoughts written to \(root.path)")
print("demo recovery key: \(recovery.formatted)")
