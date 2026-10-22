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
    let calendar: Calendar

    public init(storage: any ArchiveStorage, calendar: Calendar = .current) {
        self.storage = storage
        self.calendar = calendar
    }

    /// Moves the recording into a new Entry folder and writes its `entry.md`.
    public func createVoiceEntry(_ recording: Recording, id: String = Self.randomID()) throws -> Entry {
        let (folder, createdAt) = identity(for: recording.startedAt, id: id)
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
    public func createTypedEntry(text: String, createdAt: Date, id: String = Self.randomID()) throws -> Entry {
        let (folder, created) = identity(for: createdAt, id: id)
        let entry = Entry(
            id: id, createdAt: created, durationSeconds: nil, source: .typed, folder: folder, text: text)
        try saveText(entry)
        return entry
    }

    static let importFingerprintKey = "import_fingerprint"

    /// Writes a new Entry imported from another app. It keeps its original date, and the fingerprint of the
    /// file it came from, so importing that file again finds it.
    public func createImportedEntry(
        text: String, createdAt: Date, source: EntrySource, fingerprint: String, id: String = Self.randomID()
    ) throws -> Entry {
        let (folder, created) = identity(for: createdAt, id: id)
        let entry = Entry(id: id, createdAt: created, durationSeconds: nil, source: source, folder: folder, text: text)
        // One write, so there is never an entry.md with the fingerprint but without the thought.
        try saveText(entry, extra: [Self.importFingerprintKey: .string(fingerprint)])
        return entry
    }

    /// Fingerprints of every imported Entry, also those in the Trash.
    public func importFingerprints() throws -> Set<String> {
        let folders = try allEntryFolders() + trashedFolders()
        return Set(
            folders.compactMap { folder in
                try? document(at: "\(folder)/\(Self.documentName)").metadata[Self.importFingerprintKey]?.stringValue
            })
    }

    /// Folder and second-precise creation time for a new Entry. Folder names carry no date (ADR 0010):
    /// a synced Archive must not reveal when you recorded.
    private func identity(for date: Date, id: String) -> (folder: String, createdAt: Date) {
        ("entries/\(id)", Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)))
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

    private func saveText(
        _ entry: Entry, corrections: [VocabularyCorrection] = [], extra: [String: JSONValue] = [:]
    ) throws {
        let path = "\(entry.folder)/\(Self.documentName)"
        var metadata: [String: JSONValue] = [:]
        if storage.exists(path), let existing = try? document(at: path) { metadata = existing.metadata }
        metadata.merge(extra) { _, new in new }
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

    static let trashFolder = "trash"

    /// Moves the Entry's folder into the app's Trash (`trash/entries/…`). Returns the trashed folder.
    public func moveToTrash(_ entry: Entry) throws -> String {
        let trashed = "\(Self.trashFolder)/\(entry.folder)"
        try storage.move(entry.folder, to: trashed)
        return trashed
    }

    /// Moves a trashed folder back to where it was and returns the Entry.
    public func restoreFromTrash(trashedFolder: String) throws -> Entry {
        let original = String(trashedFolder.dropFirst(Self.trashFolder.count + 1))
        try storage.move(trashedFolder, to: original)
        return try loadEntry(folder: original).entry
    }

    /// Removes an Entry that holds nothing worth keeping (e.g. a recording with no words in it).
    public func discard(_ entry: Entry) throws {
        try storage.remove(entry.folder)
    }

    /// Deletes a trashed Entry from tällmi by handing it to the macOS Trash.
    public func deleteFromTrash(trashedFolder: String) throws {
        try storage.moveToSystemTrash(trashedFolder)
    }

    /// Folders in the Trash, oldest first.
    public func trashedFolders() throws -> [String] {
        try storage.files(named: Self.documentName, under: Self.trashFolder).map {
            String($0.dropLast(Self.documentName.count + 1))
        }
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

    /// A random Entry id: 16 lowercase base32 characters (80 bits), unrelated to any date.
    public static func randomID() -> String {
        let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")
        var generator = SystemRandomNumberGenerator()
        return String((0..<16).map { _ in alphabet[Int.random(in: 0..<32, using: &generator)] })
    }
}
