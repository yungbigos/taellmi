import CryptoKit
import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Importing notes from Apple Notes")
struct NoteImportTests {
    /// Exactly what Notes on macOS 26 writes for "export as Markdown": the title as a heading, lines ending in
    /// two spaces, and no date anywhere in the file.
    static let exportedNote = """
        # getting active  \n  \n[ZEIT](https://www.zeit.de/): “Wer sich selbst als machtlos erlebt …”  \n\
        * Selbstwirksamkeit erleben  \n**Einflussbereiche:** politisch  \n
        """

    struct Setup {
        let archive: TemporaryDirectory
        let scratch: TemporaryDirectory
        let notes: TemporaryDirectory
        let files: EntryFileStore

        init() throws {
            archive = try TemporaryDirectory()
            scratch = try TemporaryDirectory()
            notes = try TemporaryDirectory()
            files = EntryFileStore(
                storage: EncryptedStorage(
                    root: archive.url, key: SymmetricKey(size: .bits256), decryptedCache: scratch.url),
                calendar: berlinCalendar)
        }

        var importer: NoteImport {
            NoteImport(files: files, source: .appleNotes, extensions: ["md", "txt"])
        }

        /// A note file, dated like the file Notes wrote.
        @discardableResult
        func note(_ name: String, _ text: String = exportedNote, created: Date = sampleDate) throws -> URL {
            try note(name, data: Data(text.utf8), created: created)
        }

        @discardableResult
        func note(_ name: String, data: Data, created: Date = sampleDate) throws -> URL {
            let url = notes.url.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            try FileManager.default.setAttributes(
                [.creationDate: created, .modificationDate: created.addingTimeInterval(3600)], ofItemAtPath: url.path)
            return url
        }
    }

    @Test("a note becomes an encrypted thought from Apple Notes, its Text exactly as in the file, dated by the file")
    func importsOneNote() throws {
        let setup = try Setup()
        let url = try setup.note("getting active.md")

        let report = try setup.importer.run([url])

        #expect(report.alreadyHere.isEmpty)
        #expect(report.failed.isEmpty)
        let entry = try #require(report.imported.first)
        #expect(report.imported.count == 1)
        #expect(entry.source == .appleNotes)
        #expect(entry.text == Self.exportedNote, "kept exactly, title line and trailing spaces included")
        #expect(entry.title == nil, "the title stays the first line of the Text, as Notes wrote it")
        #expect(entry.createdAt == sampleDate, "the earlier of the file's creation and modification date")
        #expect(entry.durationSeconds == nil)

        let loaded = try setup.files.loadEntry(folder: entry.folder).entry
        #expect(loaded == entry)
        let onDisk = try Data(contentsOf: setup.archive.url.appendingPathComponent("\(entry.folder)/entry.md"))
        #expect(!String(decoding: onDisk, as: UTF8.self).contains("getting active"), "encrypted like every thought")
        #expect(FileManager.default.fileExists(atPath: url.path), "the exported file is left where it was")
    }

    @Test("importing the same note again, under any name, never makes a second thought")
    func skipsDuplicates() throws {
        let setup = try Setup()
        let first = try setup.note("getting active.md")
        #expect(try setup.importer.run([first]).imported.count == 1)

        let renamed = try setup.note("again/getting active copy.md")
        let changed = try setup.note("again/edited.md", Self.exportedNote + "noch ein Gedanke\n")
        let report = try setup.importer.run([first, renamed, changed])

        #expect(report.alreadyHere == ["getting active.md", "getting active copy.md"])
        #expect(report.imported.map(\.text) == [Self.exportedNote + "noch ein Gedanke\n"], "an edited note is new")
        #expect(try setup.files.allEntryFolders().count == 2)
    }

    @Test("a note you moved to the trash counts as already here")
    func trashedNotesAreNotImportedAgain() throws {
        let setup = try Setup()
        let url = try setup.note("getting active.md")
        let entry = try #require(try setup.importer.run([url]).imported.first)
        _ = try setup.files.moveToTrash(entry)

        #expect(try setup.importer.run([url]).alreadyHere == ["getting active.md"])
    }

    @Test("a chosen folder imports every note in it and its subfolders, oldest first, and ignores other files")
    func importsFolders() throws {
        let setup = try Setup()
        try setup.note("ideas/b.md", "zweiter Gedanke", created: sampleDate.addingTimeInterval(60))
        try setup.note("ideas/deeper/a.txt", "erster Gedanke", created: sampleDate)
        try setup.note("ideas/photo.png", data: Data([0x89, 0x50]))
        try setup.note("ideas/.hidden.md", "versteckt")

        let report = try setup.importer.run([setup.notes.url.appendingPathComponent("ideas")])

        #expect(report.imported.map(\.text) == ["erster Gedanke", "zweiter Gedanke"])
        #expect(report.failed.isEmpty)
    }

    @Test("empty files, files that aren't text, and chosen files of another kind fail, each with its reason")
    func reportsFailures() throws {
        let setup = try Setup()
        let empty = try setup.note("empty.md", "  \n")
        let binary = try setup.note("binary.md", data: Data([0xFF, 0xFE, 0x00, 0xD8]))
        let photo = try setup.note("photo.png", data: Data([0x89, 0x50]))
        let missing = setup.notes.url.appendingPathComponent("gone.md")
        let good = try setup.note("good.md", "ein Gedanke")

        let report = try setup.importer.run([empty, binary, photo, missing, good])

        #expect(report.imported.count == 1)
        #expect(
            report.failed == [
                .init(file: "empty.md", problem: .empty),
                .init(file: "binary.md", problem: .notText),
                .init(file: "photo.png", problem: .notANote),
                .init(file: "gone.md", problem: .unreadable),
            ])
    }

    @Test("an edited imported thought keeps its fingerprint, so importing the file again still finds it")
    func editsKeepTheFingerprint() throws {
        let setup = try Setup()
        let url = try setup.note("getting active.md")
        var entry = try #require(try setup.importer.run([url]).imported.first)
        entry.text += "\nNachtrag: am Samstag zur Demo."
        try setup.files.saveText(entry)

        #expect(try setup.importer.run([url]).alreadyHere == ["getting active.md"])
    }

    @Test("a WhatsApp chat picked as notes becomes a thought per message, also one taken as a single note before")
    func chatsAmongNotes() throws {
        let setup = try Setup()
        let chat = try setup.note("WhatsApp Chat - You/_chat.txt", WhatsAppChatTests.selfChat)
        let note = try setup.note("getting active.md")
        // How "import from apple notes" took a chat before it knew them: the whole file as one thought.
        let hash = SHA256.hash(data: Data(WhatsAppChatTests.selfChat.utf8)).map { String(format: "%02x", $0) }.joined()
        _ = try setup.files.createImportedEntry(
            text: WhatsAppChatTests.selfChat, createdAt: sampleDate, source: .appleNotes, fingerprint: "sha256:\(hash)")

        let report = try setup.importer.run([chat, note])

        #expect(report.imported.map(\.source) == [.appleNotes], "the note stays a note")
        #expect(report.alreadyHere.isEmpty)
        #expect(report.failed.isEmpty)
        #expect(report.chats.imported.map(\.source) == [.whatsApp, .whatsApp])
        #expect(report.chats.imported.first?.createdAt == WhatsAppChatTests.date(2026, 9, 2, 12, 34, 31))
        #expect(report.chats.withoutWords == 2)
    }

    @Test("if tällmi can't tell which notes are already here, it imports nothing")
    func unknownArchiveImportsNothing() throws {
        let setup = try Setup()
        let url = try setup.note("getting active.md")
        let broken = NoteImport(
            files: EntryFileStore(storage: UnlistableStorage(), calendar: berlinCalendar), source: .appleNotes,
            extensions: ["md"])

        #expect(throws: (any Error).self) { try broken.run([url]) }
    }

    @Test("the note extensions setting is a comma-separated list, in any case")
    func extensionsSetting() {
        #expect(NoteImport.extensions(fromSetting: " md, Markdown ,txt,") == ["md", "markdown", "txt"])
    }
}

/// An Archive whose list of thoughts can't be read.
private struct UnlistableStorage: ArchiveStorage {
    func read(_ path: String) throws -> Data { throw CocoaError(.fileReadNoPermission) }
    func write(_ data: Data, to path: String) throws { throw CocoaError(.fileWriteNoPermission) }
    func exists(_ path: String) -> Bool { false }
    func remove(_ path: String) throws {}
    func moveToSystemTrash(_ path: String) throws {}
    func move(_ path: String, to destination: String) throws {}
    func importFile(from url: URL, to path: String) throws {}
    func files(named name: String, under folder: String) throws -> [String] { throw CocoaError(.fileReadNoPermission) }
    func readableURL(for path: String) throws -> URL { throw CocoaError(.fileReadNoPermission) }
}
