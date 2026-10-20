import CryptoKit
import Foundation
import Persistence
import Synchronization

/// A key store that lives only in memory, for tests.
public final class InMemoryKeyStore: ArchiveKeyStore {
    private struct State {
        var key: Data?
        var pending: String?
        var saved: String?
    }

    private let state = Mutex(State())

    public init() {}

    public func loadKey() throws -> SymmetricKey? { state.withLock { $0.key.map(SymmetricKey.init(data:)) } }
    public func saveKey(_ key: SymmetricKey) throws { state.withLock { $0.key = key.withUnsafeBytes { Data($0) } } }
    public func loadPendingRecoveryKey() throws -> RecoveryKey? {
        try state.withLock { $0.pending }.map { try RecoveryKey(parsing: $0) }
    }
    public func savePendingRecoveryKey(_ key: RecoveryKey) throws { state.withLock { $0.pending = key.formatted } }
    public func clearPendingRecoveryKey() throws { state.withLock { $0.pending = nil } }
    public func saveRecoveryKey(_ key: RecoveryKey) throws { state.withLock { $0.saved = key.formatted } }
    public var savedRecoveryKey: String? { state.withLock { $0.saved } }
}
