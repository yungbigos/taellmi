import CryptoKit
import Foundation
import Persistence
import Testing

@Suite("Sealing Archive files")
struct ArchiveCryptoTests {
    @Test("sealed data opens again with the same key, and is marked as sealed")
    func roundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("Grüße, honestly – ein Gedanke.".utf8)
        let sealed = try ArchiveCrypto.seal(plain, with: key)
        #expect(ArchiveCrypto.isSealed(sealed))
        #expect(!ArchiveCrypto.isSealed(plain))
        #expect(sealed.range(of: Data("Gedanke".utf8)) == nil, "no plain text inside")
        #expect(try ArchiveCrypto.open(sealed, with: key) == plain)
    }

    @Test("a different key cannot open it")
    func wrongKey() throws {
        let sealed = try ArchiveCrypto.seal(Data("geheim".utf8), with: SymmetricKey(size: .bits256))
        #expect(throws: (any Error).self) { try ArchiveCrypto.open(sealed, with: SymmetricKey(size: .bits256)) }
    }

    @Test("opening plain data is an error, not silent garbage")
    func notSealed() {
        #expect(throws: ArchiveCrypto.Error.notSealed) {
            try ArchiveCrypto.open(Data("plain".utf8), with: SymmetricKey(size: .bits256))
        }
    }
}

@Suite("Recovery Key")
struct RecoveryKeyTests {
    @Test("looks like six groups of five characters")
    func format() {
        let text = RecoveryKey.generate().formatted
        let groups = text.split(separator: "-")
        #expect(groups.count == 6)
        #expect(groups.allSatisfy { $0.count == 5 })
    }

    @Test("is accepted however it is typed: lowercase, without dashes, O for 0, l for 1")
    func lenientParsing() throws {
        let key = RecoveryKey.generate()
        let messy = key.formatted.lowercased().replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "0", with: "o").replacingOccurrences(of: "1", with: "l")
        #expect(try RecoveryKey(parsing: messy) == key)
    }

    @Test("a typo is caught by the checksum")
    func typo() throws {
        var characters = Array(RecoveryKey.generate().formatted)
        characters[0] = characters[0] == "A" ? "B" : "A"
        #expect(throws: RecoveryKey.Error.invalid) { try RecoveryKey(parsing: String(characters)) }
    }

    @Test("it unlocks the Archive key it wrapped, and no other Recovery Key does")
    func wrapAndUnwrap() throws {
        let archiveKey = SymmetricKey(size: .bits256)
        let recovery = RecoveryKey.generate()
        let keyFile = try ArchiveKeyFile(wrapping: archiveKey, with: recovery)
        let reloaded = try ArchiveKeyFile(data: keyFile.data())
        let unwrapped = try reloaded.unwrap(with: recovery)
        #expect(unwrapped.withUnsafeBytes { Data($0) } == archiveKey.withUnsafeBytes { Data($0) })
        #expect(throws: (any Error).self) { try reloaded.unwrap(with: RecoveryKey.generate()) }
    }
}
