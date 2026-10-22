import Foundation

/// What an import of WhatsApp chats did: new thoughts, how many messages were already in the Archive or had no
/// words, and chats that couldn't be imported, each with its reason.
public struct ChatImportReport: Sendable, Equatable {
    public enum Problem: String, Error, Sendable, Equatable {
        /// A file that isn't a WhatsApp chat export.
        case notAChat
        /// The file can't be read (gone, or no permission).
        case unreadable
        /// The file isn't UTF-8 text.
        case notText
        /// More than one person wrote in it; only chats with yourself are imported for now.
        case withOthers
        /// The export as WhatsApp sent it; it needs unzipping first.
        case zipped
        /// Writing a thought failed partway; the messages saved so far are here, the rest come with the next try.
        case unsaved
    }

    public struct Failure: Sendable, Equatable {
        /// The file's name, for the report.
        public var file: String
        public var problem: Problem

        public init(file: String, problem: Problem) {
            self.file = file
            self.problem = problem
        }
    }

    public var imported: [Entry]
    /// Messages that are already thoughts (also in the Trash).
    public var alreadyHere: Int
    /// Messages without words of their own: photos, voice messages, documents, deleted messages, notices.
    public var withoutWords: Int
    public var failed: [Failure]

    public init(imported: [Entry] = [], alreadyHere: Int = 0, withoutWords: Int = 0, failed: [Failure] = []) {
        self.imported = imported
        self.alreadyHere = alreadyHere
        self.withoutWords = withoutWords
        self.failed = failed
    }
}
