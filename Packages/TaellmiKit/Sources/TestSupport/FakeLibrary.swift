import Domain
import Features
import Foundation

/// An in-memory Archive for Explore tests.
public actor FakeLibrary: ExploreLibrary {
    public private(set) var savedTexts: [String: String] = [:]
    private var entries: [Entry]
    private var trash: [String: Entry] = [:]
    private var continuations: [AsyncStream<Void>.Continuation] = []

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public func search(_ query: EntryQuery) async throws -> [Entry] {
        entries
            .filter { entry in query.words.allSatisfy { entry.text.lowercased().contains($0) } }
            .filter { query.sources?.contains($0.source) ?? true }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public nonisolated func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in Task { await self.subscribe(continuation) } }
    }

    public func detail(id: String) async throws -> EntryDetail {
        guard let entry = entries.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        return EntryDetail(entry: entry, segments: [], corrections: [], recordingURL: nil)
    }

    public func saveText(id: String, text: String) async throws {
        savedTexts[id] = text
        if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].text = text }
        publish()
    }

    public func trash(id: String) async throws -> String {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        let entry = entries.remove(at: index)
        let token = "trash/\(entry.folder)"
        trash[token] = entry
        publish()
        return token
    }

    public func restore(trashedFolder: String) async throws {
        guard let entry = trash.removeValue(forKey: trashedFolder) else { throw CocoaError(.fileNoSuchFile) }
        entries.append(entry)
        publish()
    }

    public func trashed() async throws -> [TrashedEntry] {
        trash.map { TrashedEntry(entry: $0.value, trashedFolder: $0.key) }.sorted {
            $0.entry.createdAt > $1.entry.createdAt
        }
    }

    public func deleteForever(trashedFolder: String) async throws {
        trash[trashedFolder] = nil
        publish()
    }

    private func subscribe(_ continuation: AsyncStream<Void>.Continuation) { continuations.append(continuation) }
    private func publish() { for continuation in continuations { continuation.yield() } }
}
