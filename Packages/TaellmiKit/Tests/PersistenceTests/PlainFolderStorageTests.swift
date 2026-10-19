import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Archive storage (plain folder)")
struct PlainFolderStorageTests {
    @Test("writing creates missing folders and reads back the same bytes")
    func writeRead() throws {
        let temp = try TemporaryDirectory()
        let storage = PlainFolderStorage(root: temp.url)
        try storage.write(Data("Grüße".utf8), to: "a/b/c.txt")
        #expect(try storage.read("a/b/c.txt") == Data("Grüße".utf8))
        #expect(storage.exists("a/b/c.txt"))
        #expect(!storage.exists("a/b/missing.txt"))
    }

    @Test("importing a file moves it into the Archive")
    func importMoves() throws {
        let temp = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let storage = PlainFolderStorage(root: temp.url)
        let file = try outside.makeAudioFile()
        try storage.importFile(from: file, to: "entries/x/recording.m4a")
        #expect(storage.exists("entries/x/recording.m4a"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("finds every file with a given name, as sorted relative paths")
    func findsFiles() throws {
        let temp = try TemporaryDirectory()
        let storage = PlainFolderStorage(root: temp.url)
        try storage.write(Data(), to: "entries/b/entry.md")
        try storage.write(Data(), to: "entries/a/entry.md")
        try storage.write(Data(), to: "entries/a/other.md")
        #expect(try storage.files(named: "entry.md", under: "entries") == ["entries/a/entry.md", "entries/b/entry.md"])
        #expect(try storage.files(named: "entry.md", under: "nothing-here") == [])
    }

    @Test("paths cannot escape the Archive root")
    func rejectsEscapes() throws {
        let storage = PlainFolderStorage(root: try TemporaryDirectory().url)
        #expect(throws: ArchiveStorageError.invalidPath("../secret")) {
            try storage.write(Data(), to: "../secret")
        }
    }

    @Test("a symlink inside the Archive cannot be used to escape it")
    func rejectsSymlinkEscape() throws {
        let temp = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let storage = PlainFolderStorage(root: temp.url)
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("link"), withDestinationURL: outside.url)
        #expect(throws: ArchiveStorageError.invalidPath("link/secret.txt")) {
            try storage.write(Data("x".utf8), to: "link/secret.txt")
        }
    }
}
