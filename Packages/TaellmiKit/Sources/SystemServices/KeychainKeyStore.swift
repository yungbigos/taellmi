import CryptoKit
import Foundation
import Persistence
import Security

/// The Archive key and Recovery Key in this Mac's Keychain (ADR 0010). Items are readable after you
/// log in, so capture never has to ask.
public struct KeychainKeyStore: ArchiveKeyStore {
    private let service = "app.taellmi.archive"

    public init() {}

    public func loadKey() throws -> SymmetricKey? { try read("archive-key").map(SymmetricKey.init(data:)) }
    public func saveKey(_ key: SymmetricKey) throws { try write(key.withUnsafeBytes { Data($0) }, "archive-key") }

    public func loadPendingRecoveryKey() throws -> RecoveryKey? {
        try read("pending-recovery-key").map { try RecoveryKey(parsing: String(decoding: $0, as: UTF8.self)) }
    }

    public func savePendingRecoveryKey(_ key: RecoveryKey) throws {
        try write(Data(key.formatted.utf8), "pending-recovery-key")
    }

    public func clearPendingRecoveryKey() throws { try delete("pending-recovery-key") }

    public func saveRecoveryKey(_ key: RecoveryKey) throws {
        try write(Data(key.formatted.utf8), "recovery-key", label: "tällmi recovery key")
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(_ account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    /// Updates the item in place, adding it only if it doesn't exist yet: the only copy of the key is never
    /// deleted before its replacement is safely written.
    private func write(_ data: Data, _ account: String, label: String? = nil) throws {
        var attributes: [String: Any] = [kSecValueData as String: data]
        if let label { attributes[kSecAttrLabel as String] = label }
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var item = query(account).merging(attributes) { _, new in new }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    private func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, Equatable {
    public var status: OSStatus
}
