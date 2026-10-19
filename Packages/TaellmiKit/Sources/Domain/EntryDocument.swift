import Foundation

/// The `entry.md` file of an entry: flat front matter plus a Markdown body.
///
/// Front matter values are written as single-line JSON, which is also valid YAML,
/// so the file opens cleanly in Obsidian and any YAML-aware tool without a YAML dependency.
public struct EntryDocument: Sendable, Equatable {
    public enum ParseError: Error, Equatable {
        case missingFrontMatter
        /// The 1-based front-matter line that could not be read. The content is left out on purpose,
        /// because it may be personal and errors end up in logs and the UI.
        case invalidLine(Int)
    }

    public var metadata: [String: JSONValue]
    public var body: String

    public init(metadata: [String: JSONValue], body: String) {
        self.metadata = metadata
        self.body = body
    }

    public init(markdown: String) throws {
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
            throw ParseError.missingFrontMatter
        }
        var metadata: [String: JSONValue] = [:]
        let decoder = JSONDecoder()
        for (offset, line) in lines[1..<end].enumerated() {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.invalidLine(offset + 2) }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let raw = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            do {
                metadata[key] = try decoder.decode(JSONValue.self, from: Data(raw.utf8))
            } catch {
                throw ParseError.invalidLine(offset + 2)
            }
        }
        lines.removeSubrange(...end)
        if lines.first == "" { lines.removeFirst() }
        self.init(metadata: metadata, body: lines.joined(separator: "\n"))
    }

    public func markdown() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var text = "---\n"
        for key in metadata.keys.sorted() {
            let value = metadata[key] ?? .null
            let encoded = (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            text += "\(key): \(encoded)\n"
        }
        return text + "---\n\n" + body
    }
}
