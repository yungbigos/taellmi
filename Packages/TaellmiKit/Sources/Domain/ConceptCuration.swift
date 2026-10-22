import Foundation

/// A Concept by kind and name, as you see it. Names compare without case: "marlen" is "Marlen".
public struct ConceptName: Sendable, Hashable, Codable {
    public var kind: String
    public var name: String

    public init(kind: String, name: String) {
        self.kind = kind
        self.name = name
    }

    /// The same key the graph's concept ids use.
    public var key: String { "\(kind):\(name.lowercased())" }

    public static func == (lhs: ConceptName, rhs: ConceptName) -> Bool { lhs.key == rhs.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// Your renames, merges and kind changes of Concepts (Curation, issue #47): every name the model may use is
/// sent to the Concept you chose. It is never recomputed; analysis follows it.
public struct ConceptCuration: Sendable, Equatable {
    /// Where each name goes, by its key, with the name as it was written (for splitting off again).
    public private(set) var aliases: [String: Alias] = [:]
    /// Your spelling of a concept whose key stays the same (Malin → malin).
    public private(set) var spellings: [String: String] = [:]
    /// Groups of concepts you said are not the same (suggestions you dismissed), as sorted keys "a|b".
    public private(set) var dismissed: Set<String> = []

    public struct Alias: Sendable, Equatable, Codable {
        public var from: ConceptName
        public var to: ConceptName
        /// Merged into another concept (can be split off), rather than renamed.
        public var isMerge: Bool
    }

    public init() {}

    /// Where a name ends up, following renames and merges, in your spelling.
    public func resolve(_ concept: ConceptName) -> ConceptName {
        var current = concept
        var seen: Set<String> = [current.key]
        while let next = aliases[current.key]?.to, !seen.contains(next.key) {
            seen.insert(next.key)
            current = next
        }
        if let spelling = spellings[current.key] { current.name = spelling }
        return current
    }

    public mutating func rename(_ concept: ConceptName, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let target = resolve(concept)
        let renamed = ConceptName(kind: target.kind, name: trimmed)
        if renamed.key == target.key {
            spellings[target.key] = trimmed
        } else {
            move(target, to: renamed, isMerge: false)
        }
    }

    public mutating func changeKind(_ concept: ConceptName, to kind: String) {
        let target = resolve(concept)
        move(target, to: ConceptName(kind: kind, name: target.name), isMerge: false)
    }

    /// Several concepts become one; `target` is the name that stays, even if it was merged elsewhere before.
    public mutating func merge(_ concepts: [ConceptName], into target: ConceptName) {
        let destination: ConceptName
        if aliases[target.key] != nil {
            aliases[target.key] = nil
            destination = resolve(target)
        } else {
            destination = resolve(target)
        }
        for concept in concepts {
            let source = resolve(concept)
            guard source.key != destination.key else { continue }
            move(source, to: destination, isMerge: true)
        }
    }

    /// A merged name becomes its own concept again.
    public mutating func split(_ concept: ConceptName) {
        aliases[concept.key] = nil
    }

    /// Every name merged into a concept (renames don't count: there is nothing to split off).
    public func mergedNames(into concept: ConceptName) -> [ConceptName] {
        let target = resolve(concept)
        return aliases.values.filter { $0.isMerge && resolve($0.from).key == target.key }.map(\.from)
    }

    public mutating func dismissSuggestion(_ concepts: [ConceptName]) {
        dismissed.insert(Self.group(concepts))
    }

    public func isDismissed(_ concepts: [ConceptName]) -> Bool {
        dismissed.contains(Self.group(concepts))
    }

    private static func group(_ concepts: [ConceptName]) -> String {
        concepts.map(\.key).sorted().joined(separator: "|")
    }

    /// Sends `source` (a concept of its own) and everything that already went to it to `destination`.
    private mutating func move(_ source: ConceptName, to destination: ConceptName, isMerge: Bool) {
        guard source.key != destination.key else { return }
        for (key, alias) in aliases where alias.to.key == source.key { aliases[key]?.to = destination }
        aliases[source.key] = Alias(from: source, to: destination, isMerge: isMerge)
        aliases[destination.key] = nil
        spellings[source.key] = nil
    }

    // MARK: As JSON in curation.json

    public var json: JSONValue {
        func name(_ n: ConceptName) -> JSONValue { .object(["kind": .string(n.kind), "name": .string(n.name)]) }
        return .object([
            "aliases": .array(
                aliases.values.sorted { $0.from.key < $1.from.key }.map {
                    .object(["from": name($0.from), "to": name($0.to), "merge": .bool($0.isMerge)])
                }),
            "spellings": .object(spellings.mapValues(JSONValue.string)),
            "dismissed": .array(dismissed.sorted().map(JSONValue.string)),
        ])
    }

    public init(json: JSONValue?) {
        func name(_ value: JSONValue?) -> ConceptName? {
            guard let fields = value?.objectValue, let kind = fields["kind"]?.stringValue,
                let name = fields["name"]?.stringValue
            else { return nil }
            return ConceptName(kind: kind, name: name)
        }
        let fields = json?.objectValue
        for item in fields?["aliases"]?.arrayValue ?? [] {
            guard let from = name(item.objectValue?["from"]), let to = name(item.objectValue?["to"]) else { continue }
            aliases[from.key] = Alias(from: from, to: to, isMerge: item.objectValue?["merge"]?.boolValue ?? true)
        }
        spellings = (fields?["spellings"]?.objectValue ?? [:]).compactMapValues(\.stringValue)
        dismissed = Set((fields?["dismissed"]?.arrayValue ?? []).compactMap(\.stringValue))
    }
}
