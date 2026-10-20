import Foundation

/// Where an Entry came from. An open value, so new import sources need no code change.
public struct EntrySource: RawRepresentable, Sendable, Hashable, Codable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let voice = EntrySource(rawValue: "voice")
    public static let typed = EntrySource(rawValue: "typed")
    public static let appleNotes = EntrySource(rawValue: "apple_notes")

    /// Imported from another app. Its date may be a guess (e.g. when the note was exported), so you can change it.
    public var isImported: Bool { self != .voice && self != .typed }
}

/// One act of capture. Canonical in the Archive; the database holds an index of it.
public struct Entry: Sendable, Equatable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var durationSeconds: Double?
    public var source: EntrySource
    public var title: String?
    /// Folder relative to the Archive root, e.g. `entries/<random id>`.
    public var folder: String
    /// The Entry's Text. Empty until a voice Entry is first transcribed; after that only the user changes it.
    public var text: String
    /// The model that produced the Entry's Transcript, while the Transcript is kept.
    public var transcriptModelID: String?

    public init(
        id: String, createdAt: Date, durationSeconds: Double?, source: EntrySource, title: String? = nil,
        folder: String, text: String = "", transcriptModelID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.source = source
        self.title = title
        self.folder = folder
        self.text = text
        self.transcriptModelID = transcriptModelID
    }
}
