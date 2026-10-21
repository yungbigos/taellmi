import Domain
import Foundation

extension ExploreViewModel {
    /// Each action returns whether it was saved, so ⌘Z is registered only for changes that happened.
    @discardableResult
    public func renameConcept(_ concept: ConceptSummary, to name: String, spell: Bool) async -> Bool {
        await editConcepts(spelling: spell ? name : nil) {
            $0.rename(ConceptName(kind: concept.kind, name: concept.name), to: name)
        }
    }

    /// Several concepts become one; `target` is the name that stays.
    @discardableResult
    public func mergeConcepts(_ concepts: [ConceptSummary], into target: ConceptName, spell: Bool) async -> Bool {
        await editConcepts(spelling: spell ? target.name : nil) {
            $0.merge(concepts.map { ConceptName(kind: $0.kind, name: $0.name) }, into: target)
        }
    }

    @discardableResult
    public func changeKind(_ concept: ConceptSummary, to kind: String) async -> Bool {
        await editConcepts { $0.changeKind(ConceptName(kind: concept.kind, name: concept.name), to: kind) }
    }

    /// A merged name becomes its own concept again.
    @discardableResult
    public func split(_ name: ConceptName) async -> Bool {
        await editConcepts { $0.split(name) }
    }

    /// The names merged into a concept, to split off again.
    public func mergedNames(into concept: ConceptSummary) -> [ConceptName] {
        conceptCuration.mergedNames(into: ConceptName(kind: concept.kind, name: concept.name))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// ⌘Z: the concepts as they were before the last change.
    public func undoConceptChange() async {
        guard let previous = conceptHistory.popLast() else { return }
        await editConcepts(remember: false) { $0 = previous }
    }

    /// Not the same after all: no ⌘Z step of its own, so undo keeps undoing your real changes.
    public func dismissSuggestion(_ group: [ConceptSummary]) async {
        await editConcepts(remember: false) {
            $0.dismissSuggestion(group.map { ConceptName(kind: $0.kind, name: $0.name) })
        }
    }

    /// Changes run one after another, each on the newest list, so quick clicks never lose one.
    @discardableResult
    func editConcepts(
        spelling: String? = nil, remember: Bool = true, _ change: @escaping (inout ConceptCuration) -> Void
    ) async -> Bool {
        let before = conceptQueue
        let task = Task { [weak self] () -> Bool in
            _ = await before?.value
            guard let self else { return false }
            var next = conceptCuration
            change(&next)
            return await saveConcepts(next, spelling: spelling, remember: remember)
        }
        conceptQueue = task
        return await task.value
    }

    private func saveConcepts(_ next: ConceptCuration, spelling: String?, remember: Bool) async -> Bool {
        let previous = conceptCuration
        // Which concept is open, before the index changes under it.
        var shown: ConceptSummary?
        if case .concept(let id) = stackGroup { shown = stackIndex.concepts.first { $0.id == id } }
        do {
            try await library.saveConceptCuration(next, addSpelling: spelling)
        } catch {
            errorMessage = "couldn't change that concept. try again."
            return false
        }
        if remember { conceptHistory.append(previous) }
        conceptCuration = next
        if let shown {
            let target = next.resolve(ConceptName(kind: shown.kind, name: shown.name))
            stackGroup = .concept("concept:\(target.key)")
        }
        // The index shows the change at once; the full refresh below may be overtaken by the change notice.
        if let index = try? await library.stackIndex() { stackIndex = index }
        await refresh()
        return true
    }

    func updateConceptSuggestions() {
        conceptSuggestions = ConceptSuggestions.groups(
            stackIndex.concepts, curation: conceptCuration, rule: suggestionRule)
    }
}

/// How alike two names must sound to be suggested as maybe the same (config).
public struct SuggestionRule: Sendable, Equatable {
    /// Shorter sound codes are too common to tell names apart.
    public var minCodeLength: Int
    /// How many sounds may differ.
    public var maxDistance: Int

    public init(minCodeLength: Int = 3, maxDistance: Int = 1) {
        self.minCodeLength = minCodeLength
        self.maxDistance = maxDistance
    }
}

/// Which concepts might be the same one: same kind, names that sound alike (Kölner Phonetik), not dismissed.
public enum ConceptSuggestions {
    public static func groups(
        _ concepts: [ConceptSummary], curation: ConceptCuration, rule: SuggestionRule = SuggestionRule()
    ) -> [[ConceptSummary]] {
        var groups: [[ConceptSummary]] = []
        for kind in Set(concepts.map(\.kind)).sorted() {
            let ofKind = concepts.filter { $0.kind == kind }
            var parent = Array(ofKind.indices)
            func root(_ index: Int) -> Int { parent[index] == index ? index : root(parent[index]) }
            let codes = ofKind.map { KoelnerPhonetik.code($0.name) }
            for a in ofKind.indices {
                for b in ofKind.indices where b > a && alike(codes[a], codes[b], rule) { parent[root(b)] = root(a) }
            }
            let grouped = Dictionary(grouping: ofKind.indices, by: root).values
                .map { $0.map { ofKind[$0] } }
                .filter { $0.count > 1 }
                .filter { !curation.isDismissed($0.map { ConceptName(kind: $0.kind, name: $0.name) }) }
            groups += grouped.sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }
        }
        return groups
    }

    /// The same sound code, or one sound apart, for names long enough to tell.
    static func alike(_ a: String, _ b: String, _ rule: SuggestionRule) -> Bool {
        guard a.count >= rule.minCodeLength, b.count >= rule.minCodeLength else { return false }
        return a == b || distance(a, b) <= rule.maxDistance
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
}

/// A rename or merge waiting for your input in a sheet.
public enum ConceptEdit: Identifiable, Sendable, Equatable {
    case rename(ConceptSummary)
    case merge([ConceptSummary])

    public var id: String {
        switch self {
        case .rename(let concept): "rename:\(concept.id)"
        case .merge(let concepts): "merge:" + concepts.map(\.id).joined(separator: ",")
        }
    }
}
