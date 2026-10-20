import Config
import Foundation
import Persistence

/// The Archive needs the Recovery Key on this Mac before tällmi can start.
public struct ArchiveLockedError: Error {
    public let vault: ArchiveVault
}

/// The chosen Archive folder can't be reached (unmounted drive, missing folder).
public struct ArchiveUnavailableError: Error {}

/// The chosen folder already holds a tällmi Archive, but this Mac's Archive has thoughts too.
public struct AdoptRefusedError: Error {}

/// How a chosen folder is remembered across launches: security-scoped bookmarks in the app,
/// plain paths in tests.
nonisolated struct FolderBookmarks: Sendable {
    let encode: @Sendable (URL) throws -> String
    let decode: @Sendable (String) throws -> (url: URL, isStale: Bool)

    static let securityScoped = FolderBookmarks(
        encode: { try $0.bookmarkData(options: .withSecurityScope).base64EncodedString() },
        decode: { text in
            guard let data = Data(base64Encoded: text) else { throw ArchiveUnavailableError() }
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            _ = url.startAccessingSecurityScopedResource()
            return (url, stale)
        })

    static let paths = FolderBookmarks(encode: { $0.path }, decode: { (URL(fileURLWithPath: $0), false) })
}

/// Where the Archive lives: the Library folder by default, or a folder named "tällmi" inside a folder you
/// chose. Changing it takes effect at the next start, before anything reads or writes the Archive.
nonisolated enum ArchiveLocation {
    static let folderName = "tällmi"

    static func resolve(
        settings: SettingsStore, editor: ConfigEditor, default fallback: URL,
        bookmarks: FolderBookmarks = .securityScoped
    ) throws -> URL {
        let saved = (try? settings.string(SettingKeys.archiveLocationBookmark)) ?? ""
        guard !saved.isEmpty else { return fallback }
        guard let (parent, isStale) = try? bookmarks.decode(saved) else { throw ArchiveUnavailableError() }
        if isStale, let fresh = try? bookmarks.encode(parent) {
            try? editor.setSetting(SettingKeys.archiveLocationBookmark, to: .string(fresh))
        }
        let root = parent.appendingPathComponent(folderName, isDirectory: true)
        // Never quietly start a fresh Archive where the real one should be.
        guard
            FileManager.default.fileExists(atPath: root.appendingPathComponent("archive.key").path)
                || FileManager.default.fileExists(atPath: root.appendingPathComponent(".archive.key.icloud").path)
        else { throw ArchiveUnavailableError() }
        return root
    }

    /// Remembers the folder you chose; the move happens at the next start. Refuses right away when the folder
    /// holds another tällmi Archive while the current one has thoughts.
    static func scheduleMove(
        toParent parent: URL, current: URL, editor: ConfigEditor, bookmarks: FolderBookmarks = .securityScoped
    ) throws {
        let target = parent.appendingPathComponent(folderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.appendingPathComponent("archive.key").path),
            target.standardizedFileURL != current.standardizedFileURL, holdsThoughts(current)
        {
            throw AdoptRefusedError()
        }
        try editor.setSetting(SettingKeys.archivePendingMoveBookmark, to: .string(bookmarks.encode(parent)))
    }

    /// Runs a scheduled move before the Archive is opened. If the chosen folder already holds a tällmi
    /// Archive, it is adopted as it is. Otherwise the current Archive is copied there, checked file by file,
    /// switched to, and only then removed. Any failure leaves everything as it was.
    static func applyPendingMove(
        settings: SettingsStore, editor: ConfigEditor, default fallback: URL,
        bookmarks: FolderBookmarks = .securityScoped
    ) throws {
        let pending = (try? settings.string(SettingKeys.archivePendingMoveBookmark)) ?? ""
        guard !pending.isEmpty else { return }
        defer { try? editor.setSetting(SettingKeys.archivePendingMoveBookmark, to: .string("")) }
        let parent = try bookmarks.decode(pending).url
        let target = parent.appendingPathComponent(folderName, isDirectory: true)
        let current = try resolve(settings: settings, editor: editor, default: fallback, bookmarks: bookmarks)
        guard target.standardizedFileURL != current.standardizedFileURL else { return }

        if FileManager.default.fileExists(atPath: target.appendingPathComponent("archive.key").path) {
            // Adopting replaces this Mac's Archive key; only safe while the current Archive holds nothing.
            guard !holdsThoughts(current) else { throw AdoptRefusedError() }
            try editor.setSetting(SettingKeys.archiveLocationBookmark, to: .string(pending))
            return
        }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw CocoaError(.fileWriteFileExists) }
        do {
            try FileManager.default.copyItem(at: current, to: target)
            guard sizes(in: target) == sizes(in: current) else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        try editor.setSetting(SettingKeys.archiveLocationBookmark, to: .string(pending))
        try FileManager.default.removeItem(at: current)
    }

    private static func holdsThoughts(_ root: URL) -> Bool {
        !((try? PlainFolderStorage(root: root).files(named: "entry.md", under: "entries")) ?? []).isEmpty
    }

    /// Relative path → size of every file, to check a copy.
    private static func sizes(in folder: URL) -> [String: Int] {
        var result: [String: Int] = [:]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        let prefix = folder.standardizedFileURL.path.count
        while let url = enumerator?.nextObject() as? URL {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            result[String(url.standardizedFileURL.path.dropFirst(prefix))] = size
        }
        return result
    }
}
