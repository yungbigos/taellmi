import Domain
import Foundation

/// Reads and writes `curation.json` in the Archive: everything the user decided by hand (ADR 0004).
/// Only the parts this version understands are touched; any other keys are kept as they are.
public struct CurationStore: Sendable {
    public enum Error: Swift.Error, Equatable {
        case blankTerm
        case blankName
        case duplicateName
        case unknownFolder
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

    // MARK: Folders: `folders` lists them in the order made, `filed` maps a thought to its one folder.

    public func folders() throws -> [ThoughtFolder] {
        (try document()["folders"]?.arrayValue ?? []).compactMap { item in
            guard let fields = item.objectValue, let id = fields["id"]?.stringValue,
                let name = fields["name"]?.stringValue
            else { return nil }
            return ThoughtFolder(id: id, name: name)
        }
    }

    public func filed() throws -> [String: String] {
        (try document()["filed"]?.objectValue ?? [:]).compactMapValues(\.stringValue)
    }

    @discardableResult
    public func createFolder(named name: String) throws -> ThoughtFolder {
        let folder = ThoughtFolder(id: UUID().uuidString.lowercased(), name: try validName(name, except: nil))
        try setFolders(try folders() + [folder], filed: try filed())
        return folder
    }

    public func renameFolder(_ id: String, to name: String) throws {
        let name = try validName(name, except: id)
        var folders = try folders()
        guard let index = folders.firstIndex(where: { $0.id == id }) else { throw Error.unknownFolder }
        folders[index].name = name
        try setFolders(folders, filed: try filed())
    }

    /// Its thoughts become loose; they are never deleted with it.
    public func deleteFolder(_ id: String) throws {
        try setFolders(try folders().filter { $0.id != id }, filed: try filed().filter { $0.value != id })
    }

    /// Files a thought in a folder, or makes it loose with `nil`.
    public func file(_ entryID: String, in folderID: String?) throws {
        var filed = try filed()
        if let folderID {
            guard try folders().contains(where: { $0.id == folderID }) else { throw Error.unknownFolder }
            filed[entryID] = folderID
        } else {
            filed[entryID] = nil
        }
        try setFolders(try folders(), filed: filed)
    }

    private func validName(_ name: String, except id: String?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.blankName }
        if try folders().contains(where: { $0.id != id && $0.name.lowercased() == trimmed.lowercased() }) {
            throw Error.duplicateName
        }
        return trimmed
    }

    private func setFolders(_ folders: [ThoughtFolder], filed: [String: String]) throws {
        var document = try document()
        document["folders"] = .array(folders.map { .object(["id": .string($0.id), "name": .string($0.name)]) })
        document["filed"] = .object(filed.mapValues(JSONValue.string))
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
