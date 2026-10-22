import CryptoKit
import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Importing chats from WhatsApp")
struct ChatImportTests {
    struct Setup {
        let archive: TemporaryDirectory
        let scratch: TemporaryDirectory
        let exports: TemporaryDirectory
        let files: EntryFileStore

        init() throws {
            archive = try TemporaryDirectory()
            scratch = try TemporaryDirectory()
            exports = try TemporaryDirectory()
            files = EntryFileStore(
                storage: EncryptedStorage(
                    root: archive.url, key: SymmetricKey(size: .bits256), decryptedCache: scratch.url),
                calendar: berlinCalendar)
        }

        var importer: ChatImport { ChatImport(files: files, calendar: berlinCalendar) }

        @discardableResult
        func file(_ path: String, _ text: String) throws -> URL {
            try file(path, data: Data(text.utf8))
        }

        @discardableResult
        func file(_ path: String, data: Data) throws -> URL {
            let url = exports.url.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        }
    }

    @Test("each message with words becomes an encrypted thought from WhatsApp, dated when it was sent")
    func importsMessages() throws {
        let setup = try Setup()
        let url = try setup.file("WhatsApp Chat - You/_chat.txt", WhatsAppChatTests.selfChat)

        let report = try setup.importer.run([url])

        #expect(
            report.imported.map(\.text) == [
                "Zählerstand ablesen  und notieren\nZähler-ID: 1ABC0000000000\n\nRückruf am Freitag",
                "Geschenkidee für Kim: Kletterkurs",
            ])
        #expect(report.withoutWords == 2, "the document and the voice message")
        #expect(report.alreadyHere == 0)
        #expect(report.failed.isEmpty)
        let entry = try #require(report.imported.first)
        #expect(entry.source == .whatsApp)
        #expect(entry.createdAt == WhatsAppChatTests.date(2026, 9, 2, 12, 34, 31))
        #expect(entry.title == nil)
        #expect(entry.durationSeconds == nil)

        #expect(try setup.files.loadEntry(folder: entry.folder).entry == entry)
        let onDisk = try Data(contentsOf: setup.archive.url.appendingPathComponent("\(entry.folder)/entry.md"))
        #expect(!String(decoding: onDisk, as: UTF8.self).contains("Zählerstand"), "encrypted like every thought")
        #expect(FileManager.default.fileExists(atPath: url.path), "the export is left where it was")
    }

    @Test("a later export of the same chat adds only the new messages; one in the trash counts as here")
    func importsOnlyNewMessages() throws {
        let setup = try Setup()
        let first = try setup.file("april/_chat.txt", WhatsAppChatTests.selfChat)
        let imported = try setup.importer.run([first]).imported
        _ = try setup.files.moveToTrash(try #require(imported.last))

        let later = try setup.file(
            "oktober/_chat.txt", WhatsAppChatTests.selfChat + "[03.09.26, 08:15:02] yannik: Termin beim Zahnarzt\r\n")
        let report = try setup.importer.run([later])

        #expect(report.imported.map(\.text) == ["Termin beim Zahnarzt"])
        #expect(report.alreadyHere == 2)
    }

    @Test("a chosen folder imports the chat in it; the photos, voice messages and documents beside it are ignored")
    func importsFolders() throws {
        let setup = try Setup()
        try setup.file("WhatsApp Chat - You/_chat.txt", WhatsAppChatTests.selfChat)
        try setup.file("WhatsApp Chat - You/00000014-Einkaufsliste.txt", "Milch, Eier")
        try setup.file("WhatsApp Chat - You/00000012-PHOTO-2026-09-01-09-01-00.jpg", data: Data([0xFF, 0xD8]))
        try setup.file("WhatsApp Chat - You/00000013-AUDIO-2026-09-01-09-02-00.opus", data: Data([0x4F, 0x67]))

        let report = try setup.importer.run([setup.exports.url.appendingPathComponent("WhatsApp Chat - You")])

        #expect(report.imported.count == 2)
        #expect(report.failed.isEmpty)
    }

    @Test("files that aren't a chat with yourself fail, each with its reason")
    func reportsFailures() throws {
        let setup = try Setup()
        let zipped = try setup.file("WhatsApp Chat - You.zip", data: Data([0x50, 0x4B, 0x03, 0x04]))
        let note = try setup.file("einkauf.txt", "# Einkaufsliste\n- Milch")
        let withOthers = try setup.file(
            "Kim/_chat.txt",
            "[01.09.26, 09:00:00] yannik: Kommst du mit zum Klettern?\n[01.09.26, 09:05:00] Kim: Ja, gerne")
        let binary = try setup.file("binary.txt", data: Data([0xFF, 0xFE, 0x00, 0xD8]))
        let missing = setup.exports.url.appendingPathComponent("gone/_chat.txt")

        let report = try setup.importer.run([zipped, note, withOthers, binary, missing])

        #expect(report.imported.isEmpty)
        #expect(
            report.failed == [
                .init(file: "WhatsApp Chat - You.zip", problem: .zipped),
                .init(file: "einkauf.txt", problem: .notAChat),
                .init(file: "Kim/_chat.txt", problem: .withOthers),
                .init(file: "binary.txt", problem: .notText),
                .init(file: "gone/_chat.txt", problem: .unreadable),
            ])
        #expect(try setup.files.allEntryFolders().isEmpty)
    }

    @Test(
        "a chat with anyone else isn't imported, even if only one of you wrote words: they may be the other's",
        arguments: [
            "[01.09.26, 09:00:00] Kim: \u{200E}image omitted\n[01.09.26, 09:05:00] yannik: Schönes Foto vom Gipfel",
            "[01.09.26, 09:00:00] Kim: Bis morgen am Gipfelkreuz\n[01.09.26, 09:05:00] yannik: \u{200E}image omitted",
            "[01.09.26, 09:00:00] Kim: \u{200E}Nachrichten und Anrufe sind Ende-zu-Ende-verschlüsselt.\n"
                + "[01.09.26, 09:05:00] yannik: Kommst du mit?",
        ])
    func othersWithoutWords(chat: String) throws {
        let setup = try Setup()
        let url = try setup.file("WhatsApp Chat - Kim/_chat.txt", chat)

        let report = try setup.importer.run([url])

        #expect(report.imported.isEmpty)
        #expect(report.failed == [.init(file: "WhatsApp Chat - Kim/_chat.txt", problem: .withOthers)])
    }
}
