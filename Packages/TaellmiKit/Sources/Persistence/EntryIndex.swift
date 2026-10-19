import Domain
import Foundation
import GRDB

/// The searchable index of entries in SQLite. Always rebuildable from `EntryFileStore`.
public struct EntryIndex: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func upsert(_ entry: Entry, transcript: Transcript?) throws {
        try database.writer.write { db in try Self.upsert(entry, transcript: transcript, in: db) }
    }

    public func entry(id: String) throws -> Entry? {
        try database.reader.read { db in try EntryRecord.fetchOne(db, key: id)?.entry }
    }

    public func recent(limit: Int) throws -> [Entry] {
        try database.reader.read { db in
            try EntryRecord.order(Column("created_at").desc).limit(limit).fetchAll(db).map(\.entry)
        }
    }

    /// Voice Entries that have never been transcribed, oldest first.
    public func awaitingTranscription() throws -> [Entry] {
        try database.reader.read { db in
            try EntryRecord
                .filter(Column("source") == EntrySource.voice.rawValue && Column("transcript_model_id") == nil)
                .order(Column("created_at"))
                .fetchAll(db).map(\.entry)
        }
    }

    /// The newest Entries now, and again after every change to them.
    public func recentUpdates(limit: Int) -> AsyncStream<[Entry]> {
        let observation = ValueObservation.tracking { db in
            try EntryRecord.order(Column("created_at").desc).limit(limit).fetchAll(db).map(\.entry)
        }.removeDuplicates()
        let reader = database.reader
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await entries in observation.values(in: reader) { continuation.yield(entries) }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func segments(entryID: String) throws -> [TranscriptSegment] {
        try database.reader.read { db in
            try Row.fetchAll(
                db, sql: "SELECT start_ms, end_ms, text FROM segment WHERE entry_id = ? ORDER BY ordinal",
                arguments: [entryID]
            ).map { TranscriptSegment(startMs: $0["start_ms"], endMs: $0["end_ms"], text: $0["text"]) }
        }
    }

    public struct RebuildReport: Sendable, Equatable {
        public var indexed: Int
        /// Entry folders whose `entry.md` could not be read. They are skipped, never fatal.
        public var invalidFolders: [String]
    }

    /// Re-reads every Entry folder and makes the index match the Archive exactly.
    @discardableResult
    public func rebuild(from files: EntryFileStore) throws -> RebuildReport {
        var loaded: [(entry: Entry, transcript: Transcript?)] = []
        var invalid: [String] = []
        for folder in try files.allEntryFolders() {
            do {
                loaded.append(try files.loadEntry(folder: folder))
            } catch {
                invalid.append(folder)
            }
        }
        try database.writer.write { db in
            let ids = loaded.map(\.entry.id)
            try EntryRecord.filter(!ids.contains(Column("id"))).deleteAll(db)
            for item in loaded { try Self.upsert(item.entry, transcript: item.transcript, in: db) }
        }
        return RebuildReport(indexed: loaded.count, invalidFolders: invalid)
    }

    private static func upsert(_ entry: Entry, transcript: Transcript?, in db: Database) throws {
        try EntryRecord(entry).upsert(db)
        try db.execute(sql: "DELETE FROM segment WHERE entry_id = ?", arguments: [entry.id])
        guard let transcript else { return }
        for (ordinal, segment) in transcript.segments.enumerated() {
            try db.execute(
                sql: "INSERT INTO segment (entry_id, ordinal, start_ms, end_ms, text) VALUES (?, ?, ?, ?, ?)",
                arguments: [entry.id, ordinal, segment.startMs, segment.endMs, segment.text])
        }
    }
}

struct EntryRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "entry"

    var id: String
    var createdAt: Date
    var durationS: Double?
    var source: String
    var title: String?
    var folder: String
    var text: String
    var transcriptModelId: String?

    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    init(_ entry: Entry) {
        id = entry.id
        createdAt = entry.createdAt
        durationS = entry.durationSeconds
        source = entry.source.rawValue
        title = entry.title
        folder = entry.folder
        text = entry.text
        transcriptModelId = entry.transcriptModelID
    }

    var entry: Entry {
        Entry(
            id: id, createdAt: createdAt, durationSeconds: durationS, source: EntrySource(rawValue: source),
            title: title, folder: folder, text: text, transcriptModelID: transcriptModelId)
    }
}
