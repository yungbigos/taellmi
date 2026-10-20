import Config
import Foundation
import Persistence
import TestSupport
import Testing

@testable import AppComposition

@Suite("Where the Archive lives")
struct ArchiveLocationTests {
    private func settings() throws -> (SettingsStore, ConfigEditor) {
        let database = try makeDatabase()
        _ = try Seeder(database: database).apply(SeedBundle.bundled())
        return (SettingsStore(database: database), ConfigEditor(database: database))
    }

    private func archive(at root: URL, thoughts: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("key".utf8).write(to: root.appendingPathComponent("archive.key"))
        for index in 0..<thoughts {
            let folder = root.appendingPathComponent("entries/t\(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("sealed \(index)".utf8).write(to: folder.appendingPathComponent("entry.md"))
        }
    }

    @Test("a chosen folder is moved to at the next start: copied, checked, switched, and the old one removed")
    func scheduledMove() throws {
        let (settings, editor) = try settings()
        let home = try TemporaryDirectory()
        let current = home.url.appendingPathComponent("Archive")
        try archive(at: current, thoughts: 3)
        let parent = try TemporaryDirectory()

        try ArchiveLocation.scheduleMove(toParent: parent.url, current: current, editor: editor, bookmarks: .paths)
        try ArchiveLocation.applyPendingMove(settings: settings, editor: editor, default: current, bookmarks: .paths)

        let moved = try ArchiveLocation.resolve(settings: settings, editor: editor, default: current, bookmarks: .paths)
        #expect(moved == parent.url.appendingPathComponent("tällmi", isDirectory: true))
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("entries/t2/entry.md").path))
        #expect(!FileManager.default.fileExists(atPath: current.path))
        #expect(try settings.string(SettingKeys.archivePendingMoveBookmark).isEmpty)
    }

    @Test("a folder that already holds a tällmi Archive is adopted as it is (new Mac), nothing is copied over it")
    func adoptsExisting() throws {
        let (settings, editor) = try settings()
        let home = try TemporaryDirectory()
        let current = home.url.appendingPathComponent("Archive")
        try archive(at: current, thoughts: 0)
        let parent = try TemporaryDirectory()
        try archive(at: parent.url.appendingPathComponent("tällmi"), thoughts: 5)

        try ArchiveLocation.scheduleMove(toParent: parent.url, current: current, editor: editor, bookmarks: .paths)
        try ArchiveLocation.applyPendingMove(settings: settings, editor: editor, default: current, bookmarks: .paths)

        let resolved = try ArchiveLocation.resolve(
            settings: settings, editor: editor, default: current, bookmarks: .paths)
        #expect(resolved == parent.url.appendingPathComponent("tällmi", isDirectory: true))
        #expect(FileManager.default.fileExists(atPath: resolved.appendingPathComponent("entries/t4/entry.md").path))
        #expect(FileManager.default.fileExists(atPath: current.path), "the old Archive is kept, not merged or deleted")
    }

    @Test("another tällmi Archive is never adopted while this one has thoughts, so its key isn't lost")
    func refusesAdoptOverThoughts() throws {
        let (settings, editor) = try settings()
        let home = try TemporaryDirectory()
        let current = home.url.appendingPathComponent("Archive")
        try archive(at: current, thoughts: 2)
        let parent = try TemporaryDirectory()
        try archive(at: parent.url.appendingPathComponent("tällmi"), thoughts: 5)

        #expect(throws: AdoptRefusedError.self) {
            try ArchiveLocation.scheduleMove(toParent: parent.url, current: current, editor: editor, bookmarks: .paths)
        }
        // A move scheduled before the current Archive got thoughts is refused at start too.
        try editor.setSetting(SettingKeys.archivePendingMoveBookmark, to: .string(parent.url.path))
        #expect(throws: AdoptRefusedError.self) {
            try ArchiveLocation.applyPendingMove(
                settings: settings, editor: editor, default: current, bookmarks: .paths)
        }
        #expect(
            try ArchiveLocation.resolve(settings: settings, editor: editor, default: current, bookmarks: .paths)
                == current)
    }

    @Test("a chosen folder whose tällmi Archive is gone is reported as unavailable, never silently recreated")
    func unavailable() throws {
        let (settings, editor) = try settings()
        let parent = try TemporaryDirectory()
        try editor.setSetting(SettingKeys.archiveLocationBookmark, to: .string(parent.url.path))
        #expect(throws: ArchiveUnavailableError.self) {
            try ArchiveLocation.resolve(
                settings: settings, editor: editor, default: parent.url.appendingPathComponent("x"), bookmarks: .paths)
        }
    }
}
