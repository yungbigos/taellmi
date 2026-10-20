import Foundation

/// What an import of notes did: new thoughts, notes that were already in the Archive, and notes that couldn't
/// be imported, each with its reason.
public struct NoteImportReport: Sendable, Equatable {
    public enum Problem: String, Error, Sendable, Equatable {
        /// A file you chose that isn't a note, e.g. a picture.
        case notANote
        /// The file can't be read (gone, or no permission).
        case unreadable
        /// The file isn't UTF-8 text.
        case notText
        /// The file holds no words.
        case empty
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
    /// Names of files whose note is already a thought (also in the Trash).
    public var alreadyHere: [String]
    public var failed: [Failure]

    public init(imported: [Entry] = [], alreadyHere: [String] = [], failed: [Failure] = []) {
        self.imported = imported
        self.alreadyHere = alreadyHere
        self.failed = failed
    }
}
