import Domain
import Foundation

/// "import from whatsapp …": turns a chat you exported from WhatsApp into thoughts, one for each message with
/// words, dated when it was sent. Only a chat with yourself for now: other people's words aren't your thoughts.
/// The export is only read, never moved or changed.
public struct ChatImport: Sendable {
    let files: EntryFileStore
    /// Where WhatsApp's times are read; the export doesn't say which time zone they are in.
    let calendar: Calendar

    public init(files: EntryFileStore, calendar: Calendar) {
        self.files = files
        self.calendar = calendar
    }

    /// Imports the chosen chats (`_chat.txt` files or their folders); a message already in the Archive is
    /// skipped, so a later export of the same chat adds only what is new. Throws, importing nothing, when it
    /// can't tell which messages are already here.
    public func run(_ chosen: [URL]) throws -> ChatImportReport {
        var report = ChatImportReport()
        var known = try files.importFingerprints()
        for candidate in chosen.flatMap(chatFiles) {
            let chat: WhatsAppChat
            switch read(candidate) {
            case .failure(let problem):
                report.failed.append(.init(file: Self.label(candidate), problem: problem))
                continue
            case .success(let read):
                chat = read
            }
            // Anyone else in the chat, even with only photos or the encryption notice, means the words may be
            // theirs: the export doesn't say which name is you.
            guard Set(chat.messages.map(\.sender).filter { !$0.isEmpty }).count <= 1 else {
                report.failed.append(.init(file: Self.label(candidate), problem: .withOthers))
                continue
            }
            let withWords = chat.messages.filter { $0.text.contains { !$0.isWhitespace } }
            report.withoutWords += chat.messages.count - withWords.count
            for message in withWords {
                guard !known.contains(message.fingerprint) else {
                    report.alreadyHere += 1
                    continue
                }
                do {
                    report.imported.append(
                        try files.createImportedEntry(
                            text: message.text, createdAt: message.sentAt, source: .whatsApp,
                            fingerprint: message.fingerprint))
                    known.insert(message.fingerprint)
                } catch {
                    report.failed.append(.init(file: Self.label(candidate), problem: .unsaved))
                    break
                }
            }
        }
        return report
    }

    /// What WhatsApp names the chat in every export.
    private static let chatName = "_chat.txt"

    /// A chosen file stays itself; a folder becomes the `_chat.txt` files in it. Beside one, in an unzipped
    /// export, are the chat's photos, voice messages and documents, text files included.
    private func chatFiles(_ url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [url] }
        let found = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        return (found?.allObjects as? [URL] ?? [])
            .filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                    && $0.lastPathComponent == Self.chatName
            }
            .sorted { $0.path < $1.path }
    }

    /// Every export's chat is `_chat.txt`, so the report names it with its folder, e.g.
    /// "WhatsApp Chat - You/_chat.txt".
    private static func label(_ url: URL) -> String {
        guard url.lastPathComponent == chatName else { return url.lastPathComponent }
        return "\(url.deletingLastPathComponent().lastPathComponent)/\(chatName)"
    }

    private func read(_ url: URL) -> Result<WhatsAppChat, ChatImportReport.Problem> {
        guard url.pathExtension.lowercased() != "zip" else { return .failure(.zipped) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        guard let text = String(data: data, encoding: .utf8) else { return .failure(.notText) }
        guard let chat = WhatsAppChat(text: text, calendar: calendar) else { return .failure(.notAChat) }
        return .success(chat)
    }
}
