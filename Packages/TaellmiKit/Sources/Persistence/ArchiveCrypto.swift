import CryptoKit
import Foundation

/// Seals and opens Archive files with AES-GCM (ADR 0010). Format: "TLM1" + AES-GCM combined box.
public enum ArchiveCrypto {
    public enum Error: Swift.Error, Equatable {
        case notSealed
    }

    static let header = Data("TLM1".utf8)

    public static func seal(_ data: Data, with key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw Error.notSealed }
        return header + combined
    }

    public static func open(_ data: Data, with key: SymmetricKey) throws -> Data {
        guard isSealed(data) else { throw Error.notSealed }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(header.count)), using: key)
    }

    public static func isSealed(_ data: Data) -> Bool {
        data.count > header.count && data.prefix(header.count) == header
    }
}

/// The Recovery Key: 25 random characters plus a 5-character checksum, shown as six groups of five
/// (Crockford base32: no I, L, O or U; typing O for 0 and I/L for 1 still works).
public struct RecoveryKey: Sendable, Equatable {
    public enum Error: Swift.Error, Equatable {
        case invalid
    }

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    /// 25 characters × 5 bits = 125 bits of randomness.
    let body: String

    public static func generate() -> RecoveryKey {
        var generator = SystemRandomNumberGenerator()
        return RecoveryKey(body: String((0..<25).map { _ in alphabet[Int.random(in: 0..<32, using: &generator)] }))
    }

    private init(body: String) {
        self.body = body
    }

    public init(parsing text: String) throws {
        let cleaned = text.uppercased().compactMap { character -> Character? in
            switch character {
            case "O": "0"
            case "I", "L": "1"
            case let c where Self.alphabet.contains(c): c
            default: nil
            }
        }
        guard cleaned.count == 30 else { throw Error.invalid }
        let body = String(cleaned.prefix(25))
        guard String(cleaned.suffix(5)) == Self.checksum(of: body) else { throw Error.invalid }
        self.body = body
    }

    public var formatted: String {
        let all = Array(body + Self.checksum(of: body))
        return stride(from: 0, to: 30, by: 5).map { String(all[$0..<$0 + 5]) }.joined(separator: "-")
    }

    /// The last group, which you type back to confirm you saved the key.
    public var lastGroup: String { String(formatted.suffix(5)) }

    /// The key that wraps the Archive key, derived from the Recovery Key.
    func wrappingKey(salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(body.utf8)), salt: salt,
            info: Data("tällmi archive key".utf8), outputByteCount: 32)
    }

    private static func checksum(of body: String) -> String {
        let digest = Array(SHA256.hash(data: Data(body.utf8)))
        return String((0..<5).map { alphabet[Int(digest[$0]) % 32] })
    }
}

/// `archive.key` in the Archive: a copy of the Archive key, locked with the Recovery Key, plus a check
/// value that tells whether a key from the Keychain belongs to this Archive.
public struct ArchiveKeyFile: Sendable, Codable {
    public enum Error: Swift.Error, Equatable {
        case unsupportedVersion
    }

    var version = 1
    var salt: Data
    var wrapped: Data
    /// HMAC of a fixed text under the Archive key. Reveals nothing about the key.
    var check: Data?

    public init(wrapping key: SymmetricKey, with recovery: RecoveryKey) throws {
        var bytes = [UInt8](repeating: 0, count: 16)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = generator.next() }
        salt = Data(bytes)
        wrapped = try ArchiveCrypto.seal(key.withUnsafeBytes { Data($0) }, with: recovery.wrappingKey(salt: salt))
        check = Self.checkValue(for: key)
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(ArchiveKeyFile.self, from: data)
        guard version == 1 else { throw Error.unsupportedVersion }
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func unwrap(with recovery: RecoveryKey) throws -> SymmetricKey {
        SymmetricKey(data: try ArchiveCrypto.open(wrapped, with: recovery.wrappingKey(salt: salt)))
    }

    /// Whether `key` is this Archive's key.
    public func matches(_ key: SymmetricKey) -> Bool {
        check.map { $0 == Self.checkValue(for: key) } ?? true
    }

    private static func checkValue(for key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("tällmi key check".utf8), using: key))
    }
}
