import Domain
import Foundation

/// Reads and writes Entry folders in the Archive (ADR 0004).
///
/// Layout: `entries/YYYY/MM/<id>/` with `entry.md` (Text + metadata), `recording.m4a` and
/// `transcript.json`. The Text is written by the app only once, from the first Transcript;
/// after that only the user changes it.
public struct EntryFileStore: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidEntryFile(folder: String, reason: String)
    }

    /// An Entry as read back from the Archive.
    public struct LoadedEntry: Sendable, Equatable {
        public var entry: Entry
        public var transcript: Transcript?
        /// Vocabulary corrections the app made when it first wrote the Text.
        public var corrections: [VocabularyCorrection]
    }

    static let correctionsKey = "vocabulary_corrections"

    static let documentName = "entry.md"
    static let recordingName = "recording.m4a"
    static let transcriptName = "transcript.json"

    public let storage: any ArchiveStorage
    private let calendar: Calendar

    public init(storage: any ArchiveStorage, calendar: Calendar = .current) {
        self.storage = storage
        self.calendar = calendar
    }

    /// Moves the recording into a new Entry folder and writes its `entry.md`.
    public func createVoiceEntry(_ recording: Recording, suffix: String = Self.randomSuffix()) throws -> Entry {
        let (id, folder, createdAt) = identity(for: recording.startedAt, suffix: suffix)
        let entry = Entry(
            id: id, createdAt: createdAt, durationSeconds: recording.durationSeconds, source: .voice, folder: folder)
        try saveText(entry)
        do {
            try storage.importFile(from: recording.file, to: "\(folder)/\(Self.recordingName)")
        } catch {
            try? storage.remove(folder)  // no half-made Entry without its recording
            throw error
        }
        return entry
    }

    /// Writes a new typed Entry: its Text is there from the start, and there is no recording.
    public func createTypedEntry(text: String, createdAt: Date, suffix: String = Self.randomSuffix()) throws -> Entry {
        let (id, folder, created) = identity(for: createdAt, suffix: suffix)
        let entry = Entry(
            id: id, createdAt: created, durationSeconds: nil, source: .typed, folder: folder, text: text)
        try saveText(entry)
        return entry
    }

    /// Id, folder and second-precise creation time for a new Entry.
    private func identity(for date: Date, suffix: String) -> (id: String, folder: String, createdAt: Date) {
        let createdAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: createdAt)
        let id = String(
            format: "%04d%02d%02d-%02d%02d%02d-%@", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, suffix)
        let folder = String(format: "entries/%04d/%02d/%@", parts.year ?? 0, parts.month ?? 0, id)
        return (id, folder, createdAt)
    }

    /// Stores the Transcript. Only the very first Transcript of an Entry becomes its Text (as `firstText`
    /// if given, e.g. after Vocabulary correction); everything else in `entry.md`, including edits made on
    /// disk, is left as it is.
    public func saveTranscript(
        _ transcript: Transcript, for entry: Entry, firstText: String? = nil,
        corrections: [VocabularyCorrection] = []
    ) throws -> Entry {
        let transcriptPath = "\(entry.folder)/\(Self.transcriptName)"
        let isFirstTranscript = !storage.exists(transcriptPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try storage.write(try encoder.encode(transcript), to: transcriptPath)

        var current = try loadEntry(folder: entry.folder).entry
        if isFirstTranscript, current.text.isEmpty {
            current.text = firstText ?? transcript.text
            try saveText(current, corrections: corrections)
        }
        return current
    }

    /// Writes the Entry's metadata and Text to `entry.md`, keeping front-matter keys the app doesn't know.
    public func saveText(_ entry: Entry) throws {
        try saveText(entry, corrections: [])
    }

    private func saveText(_ entry: Entry, corrections: [VocabularyCorrection]) throws {
        let path = "\(entry.folder)/\(Self.documentName)"
        var metadata: [String: JSONValue] = [:]
        if storage.exists(path), let existing = try? document(at: path) { metadata = existing.metadata }
        if !corrections.isEmpty {
            metadata[Self.correctionsKey] = .array(corrections.map { .string("\($0.from) → \($0.to)") })
        }
        metadata["id"] = .string(entry.id)
        metadata["created"] = .string(
            entry.createdAt.formatted(Date.ISO8601FormatStyle(timeZone: calendar.timeZone)))
        metadata["source"] = .string(entry.source.rawValue)
        metadata["title"] = entry.title.map(JSONValue.string) ?? .null
        metadata["duration_s"] = entry.durationSeconds.map(JSONValue.number)
        let body = entry.text.isEmpty ? "" : entry.text + "\n"
        let markdown = EntryDocument(metadata: metadata, body: body).markdown()
        try storage.write(Data(markdown.utf8), to: path)
    }

    public func hasRecording(_ entry: Entry) -> Bool {
        storage.exists("\(entry.folder)/\(Self.recordingName)")
    }

    /// Reads an Entry and its Transcript (if still kept) back from the Archive.
    public func loadEntry(folder: String) throws -> LoadedEntry {
        let document = try document(at: "\(folder)/\(Self.documentName)")
        let meta = document.metadata
        guard let id = meta["id"]?.stringValue,
            let created = meta["created"]?.stringValue.flatMap({ try? Date.ISO8601FormatStyle().parse($0) }),
            let source = meta["source"]?.stringValue
        else {
            throw Error.invalidEntryFile(folder: folder, reason: "missing id, created or source")
        }
        var text = document.body
        if text.hasSuffix("\n") { text.removeLast() }

        var transcript: Transcript?
        let transcriptPath = "\(folder)/\(Self.transcriptName)"
        if storage.exists(transcriptPath) {
            transcript = try JSONDecoder().decode(Transcript.self, from: storage.read(transcriptPath))
        }
        let entry = Entry(
            id: id, createdAt: created, durationSeconds: meta["duration_s"]?.doubleValue,
            source: EntrySource(rawValue: source), title: meta["title"]?.stringValue, folder: folder, text: text,
            transcriptModelID: transcript?.modelID)
        var corrections: [VocabularyCorrection] = []
        if case .array(let items)? = meta[Self.correctionsKey] {
            corrections = items.compactMap { item in
                let parts = item.stringValue?.components(separatedBy: " → ") ?? []
                return parts.count == 2 ? VocabularyCorrection(from: parts[0], to: parts[1]) : nil
            }
        }
        return LoadedEntry(entry: entry, transcript: transcript, corrections: corrections)
    }

    /// A readable URL of the Entry's recording, for speech-to-text.
    public func recordingURL(for entry: Entry) throws -> URL {
        try storage.readableURL(for: "\(entry.folder)/\(Self.recordingName)")
    }

    /// Relative folders of all Entries, oldest first.
    public func allEntryFolders() throws -> [String] {
        try storage.files(named: Self.documentName, under: "entries").map {
            String($0.dropLast(Self.documentName.count + 1))
        }
    }

    private func document(at path: String) throws -> EntryDocument {
        try EntryDocument(markdown: String(decoding: storage.read(path), as: UTF8.self))
    }

    public static func randomSuffix() -> String {
        String(UUID().uuidString.lowercased().prefix(4))
    }
}
