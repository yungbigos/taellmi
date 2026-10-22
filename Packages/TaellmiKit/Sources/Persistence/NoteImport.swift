import CryptoKit
import Domain
import Foundation

/// "import from apple notes …": turns note files you chose (Markdown or plain text, or folders of them) into
/// thoughts. The Text is kept exactly as in the file. A note keeps its date; Notes writes no date into its
/// exports, so that is the file's date. A WhatsApp chat among them is imported as a chat, a thought per message
/// (ADR 0015). Files are only read, never moved or changed.
public struct NoteImport: Sendable {
    let files: EntryFileStore
    let source: EntrySource
    /// File extensions that count as notes, lowercase (config: `import.note_extensions`).
    let extensions: Set<String>

    public init(files: EntryFileStore, source: EntrySource, extensions: Set<String>) {
        self.files = files
        self.source = source
        self.extensions = Set(extensions.map { $0.lowercased() })
    }

    /// The extensions in the `import.note_extensions` setting: comma-separated, any case.
    public static func extensions(fromSetting value: String) -> Set<String> {
        Set(
            value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty })
    }

    /// Imports the chosen files and folders; a note already in the Archive is skipped, so running it again
    /// is safe. Throws, importing nothing, when it can't tell which notes are already here.
    public func run(_ chosen: [URL]) throws -> NoteImportReport {
        var report = NoteImportReport()
        var known = try files.importFingerprints()
        var chats: [URL] = []
        for candidate in chosen.flatMap(noteFiles) {
            guard extensions.contains(candidate.pathExtension.lowercased()) else {
                report.failed.append(.init(file: candidate.lastPathComponent, problem: .notANote))
                continue
            }
            switch read(candidate) {
            case .failure(let problem):
                report.failed.append(.init(file: candidate.lastPathComponent, problem: problem))
            case .success(let note):
                // Before the duplicate check: a chat once taken as a single note is split now.
                guard WhatsAppChat(text: note.text, calendar: files.calendar) == nil else {
                    chats.append(candidate)
                    continue
                }
                guard !known.contains(note.fingerprint) else {
                    report.alreadyHere.append(candidate.lastPathComponent)
                    continue
                }
                do {
                    report.imported.append(
                        try files.createImportedEntry(
                            text: note.text, createdAt: note.date, source: source, fingerprint: note.fingerprint))
                    known.insert(note.fingerprint)
                } catch {
                    report.failed.append(.init(file: candidate.lastPathComponent, problem: .unreadable))
                }
            }
        }
        if !chats.isEmpty { report.chats = try ChatImport(files: files, calendar: files.calendar).run(chats) }
        return report
    }

    private struct Note {
        var text: String
        var date: Date
        var fingerprint: String
    }

    /// A chosen file stays itself (it may fail as not a note); a folder becomes the notes in it, oldest first.
    private func noteFiles(_ url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [url] }
        let found = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        let notes = (found?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && extensions.contains($0.pathExtension.lowercased())
        }
        return notes.map { ($0, Self.date(of: $0)) }
            .sorted { ($0.1, $0.0.path) < ($1.1, $1.0.path) }
            .map(\.0)
    }

    private func read(_ url: URL) -> Result<Note, NoteImportReport.Problem> {
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        guard let text = String(data: data, encoding: .utf8) else { return .failure(.notText) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .success(Note(text: text, date: Self.date(of: url), fingerprint: "sha256:\(hash)"))
    }

    /// The earlier of the file's creation and modification date: copying a file can make it look newer than
    /// its last change.
    private static func date(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return [values?.creationDate, values?.contentModificationDate].compactMap { $0 }.min() ?? Date()
    }
}
