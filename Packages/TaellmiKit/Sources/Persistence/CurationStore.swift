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

    /// The summary you wrote for a thought, which replaces the generated one for good (ADR 0012).
    public func summary(for entryID: String) throws -> String? {
        try document()["summaries"]?.objectValue?[entryID]?.stringValue
    }

    /// Saves your summary; `nil` or blank brings back the generated one.
    public func setSummary(_ text: String?, for entryID: String) throws {
        var document = try document()
        var summaries = document["summaries"]?.objectValue ?? [:]
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        summaries[entryID] = trimmed.isEmpty ? nil : .string(trimmed)
        document["summaries"] = .object(summaries)
        try write(document)
    }

    private func setVocabulary(_ terms: Set<String>) throws {
        var document = try document()
        document["vocabulary"] = .array(terms.sorted().map(JSONValue.string))
        try write(document)
    }

    private func write(_ document: [String: JSONValue]) throws {
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
