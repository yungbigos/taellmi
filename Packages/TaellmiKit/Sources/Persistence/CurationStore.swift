import Domain
import Foundation

/// Reads and writes `curation.json` in the Archive: everything the user decided by hand (ADR 0004).
/// Only the parts this version understands are touched; any other keys are kept as they are.
public struct CurationStore: Sendable {
    public enum Error: Swift.Error, Equatable {
        case blankTerm
    }

    static let fileName = "curation.json"
    private let storage: any ArchiveStorage

    public init(storage: any ArchiveStorage) {
        self.storage = storage
    }

    public func vocabulary() throws -> [VocabularyTerm] {
        guard case .array(let items)? = try document()["vocabulary"] else { return [] }
        return items.compactMap { $0.stringValue.map(VocabularyTerm.init(text:)) }
    }

    public func addToVocabulary(_ text: String) throws {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw Error.blankTerm }
        try setVocabulary(Set(try vocabulary().map(\.text)).union([term]))
    }

    public func removeFromVocabulary(_ text: String) throws {
        try setVocabulary(Set(try vocabulary().map(\.text)).subtracting([text]))
    }

    private func setVocabulary(_ terms: Set<String>) throws {
        var document = try document()
        document["vocabulary"] = .array(terms.sorted().map(JSONValue.string))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try storage.write(try encoder.encode(document), to: Self.fileName)
    }

    private func document() throws -> [String: JSONValue] {
        guard storage.exists(Self.fileName) else { return [:] }
        return try JSONDecoder().decode([String: JSONValue].self, from: storage.read(Self.fileName))
    }
}

extension CurationStore: VocabularySource {
    public func terms() async throws -> [VocabularyTerm] {
        try vocabulary()
    }
}
