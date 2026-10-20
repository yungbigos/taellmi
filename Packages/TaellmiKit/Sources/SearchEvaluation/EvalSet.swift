import Foundation

/// An evaluation set: passages to index, and searches with their known right answers.
/// Read from `corpus.jsonl` and `queries.jsonl` (see eval/README.md).
public struct EvalSet: Sendable {
    public struct Document: Sendable, Decodable {
        public var id: String
        public var text: String
        public var date: Date?

        public init(id: String, text: String, date: Date? = nil) {
            self.id = id
            self.text = text
            self.date = date
        }
    }

    public struct Query: Sendable, Decodable {
        public var id: String
        public var text: String
        public var kind: String
        /// Document ids that answer this search; empty means nothing should be found.
        public var relevant: [String]

        public init(id: String, text: String, kind: String, relevant: [String]) {
            self.id = id
            self.text = text
            self.kind = kind
            self.relevant = relevant
        }
    }

    public var name: String
    public var documents: [Document]
    public var queries: [Query]

    public init(name: String, documents: [Document], queries: [Query]) {
        self.name = name
        self.documents = documents
        self.queries = queries
    }

    /// Loads a set from a folder. `maxQueries` takes an evenly spread sample, for large sets.
    public static func load(from folder: URL, maxQueries: Int? = nil) throws -> EvalSet {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return date
        }
        func lines<T: Decodable>(_ name: String) throws -> [T] {
            try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
                .split(separator: "\n").map { try decoder.decode(T.self, from: Data($0.utf8)) }
        }
        var queries: [Query] = try lines("queries.jsonl")
        if let maxQueries, queries.count > maxQueries {
            let step = Double(queries.count) / Double(maxQueries)
            queries = (0..<maxQueries).map { queries[Int(Double($0) * step)] }
        }
        return EvalSet(name: folder.lastPathComponent, documents: try lines("corpus.jsonl"), queries: queries)
    }
}
