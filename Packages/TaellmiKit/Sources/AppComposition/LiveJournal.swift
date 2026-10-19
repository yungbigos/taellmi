import Domain
import Foundation
import Persistence
import Pipeline

/// The Journal the UI talks to: stores Entries in the Archive, indexes them, and queues processing.
struct LiveJournal: Journal {
    let files: EntryFileStore
    let index: EntryIndex
    let runner: PipelineRunner
    let archiveFolder: URL
    let kickPipeline: @Sendable () -> Void

    func addVoiceEntry(_ recording: Recording) async throws -> Entry {
        let entry = try files.createVoiceEntry(recording)
        try index.upsert(entry, transcript: nil)
        try await runner.enqueue(entry)
        kickPipeline()
        return entry
    }

    func addTypedEntry(_ text: String) async throws -> Entry {
        let entry = try files.createTypedEntry(text: text, createdAt: Date())
        try index.upsert(entry, transcript: nil)
        return entry
    }

    func recentEntries(limit: Int) async throws -> [Entry] {
        try index.recent(limit: limit)
    }

    func recentEntryUpdates(limit: Int) -> AsyncStream<[Entry]> {
        index.recentUpdates(limit: limit)
    }
}
