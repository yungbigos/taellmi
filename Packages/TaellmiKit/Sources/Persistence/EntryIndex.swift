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

    /// Removes an Entry from the index (e.g. when it goes to the Trash).
    public func remove(id: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM entry_search WHERE entry_id = ?", arguments: [id])
            _ = try EntryRecord.deleteOne(db, key: id)
        }
    }

    /// Entries matching the search words and filters, newest first. Every word must match; words of three
    /// letters or more match anywhere inside a word.
    public func search(_ query: EntryQuery, now: Date = Date(), calendar: Calendar = .current) throws -> [Entry] {
        var conditions: [String] = []
        var arguments: StatementArguments = []
        if let earliest = query.earliestDate(now: now, calendar: calendar) {
            conditions.append("created_at >= ?")
            arguments += [earliest]
        }
        if let sources = query.sources {
            conditions.append("source IN (\(sources.map { _ in "?" }.joined(separator: ", ")))")
            arguments += StatementArguments(sources.map(\.rawValue))
        }
        for word in query.words {
            if word.count >= 3 {
                conditions.append("id IN (SELECT entry_id FROM entry_search WHERE entry_search MATCH ?)")
                arguments += ["\"" + word.replacingOccurrences(of: "\"", with: "\"\"") + "\""]
            } else {
                conditions.append("id IN (SELECT entry_id FROM entry_search WHERE instr(text, ?) > 0)")
                arguments += [word]
            }
        }
        let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return try database.reader.read { db in
            try EntryRecord.fetchAll(
                db, sql: "SELECT * FROM entry \(filter) ORDER BY created_at DESC", arguments: arguments
            )
            .map(\.entry)
        }
    }

    /// How well each Entry matches any of the words (three letters or more), higher is better. Entries that
    /// match none are left out. Used to order results by relevance, not to decide what matches.
    public func keywordScores(words: [String]) throws -> [String: Double] {
        let terms = words.filter { $0.count >= 3 }.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        guard !terms.isEmpty else { return [:] }
        return try database.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT entry_id, bm25(entry_search) AS rank FROM entry_search WHERE entry_search MATCH ?",
                arguments: [terms.joined(separator: " OR ")])
            // bm25 is lower for better matches; negate so higher means more relevant.
            return Dictionary(rows.map { ($0["entry_id"], -($0["rank"] as Double)) }, uniquingKeysWith: max)
        }
    }

    public func entry(id: String) throws -> Entry? {
        try database.reader.read { db in try EntryRecord.fetchOne(db, key: id)?.entry }
    }

    public func recent(limit: Int) throws -> [Entry] {
        try database.reader.read { db in
            try EntryRecord.order(Column("created_at").desc).limit(limit).fetchAll(db).map(\.entry)
        }
    }

    /// Every Entry's id (Trash excluded, which isn't in the index).
    public func allIDs() throws -> [String] {
        try database.reader.read { db in try String.fetchAll(db, sql: "SELECT id FROM entry") }
    }

    /// Fires after every change to the Entries table.
    public func changes() -> AsyncStream<Void> {
        let writer = database.writer
        return AsyncStream { continuation in
            let observation = DatabaseRegionObservation(tracking: Table("entry"))
            let cancellable = observation.start(in: writer) { _ in
                continuation.finish()
            } onChange: { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in cancellable.cancel() }
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
        var loaded: [EntryFileStore.LoadedEntry] = []
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
            try db.execute(sql: "DELETE FROM entry_search")
            for item in loaded { try Self.upsert(item.entry, transcript: item.transcript, in: db) }
        }
        return RebuildReport(indexed: loaded.count, invalidFolders: invalid)
    }

    private static func upsert(_ entry: Entry, transcript: Transcript?, in db: Database) throws {
        try EntryRecord(entry).upsert(db)
        try db.execute(sql: "DELETE FROM entry_search WHERE entry_id = ?", arguments: [entry.id])
        try db.execute(
            sql: "INSERT INTO entry_search (entry_id, text) VALUES (?, ?)",
            // Search reads the words, not the Formatting (ADR 0014).
            arguments: [entry.id, WordsOnlyText(entry.text).words.lowercased()])
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
