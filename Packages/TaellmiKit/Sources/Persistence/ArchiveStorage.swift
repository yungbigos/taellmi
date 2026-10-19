import Foundation

public enum ArchiveStorageError: Error, Equatable {
    case invalidPath(String)
}

/// The single doorway to files in the Archive. Encryption (ADR 0004) will be a second implementation
/// of this protocol, so nothing else has to change when it arrives.
public protocol ArchiveStorage: Sendable {
    func read(_ path: String) throws -> Data
    /// Writes atomically, creating folders as needed. Replaces an existing file.
    func write(_ data: Data, to path: String) throws
    func exists(_ path: String) -> Bool
    func remove(_ path: String) throws
    /// Moves an outside file (e.g. a fresh recording) into the Archive.
    func importFile(from url: URL, to path: String) throws
    /// Relative paths of all files with this name below `folder`, sorted.
    func files(named name: String, under folder: String) throws -> [String]
    /// A readable file URL for tools that need one (e.g. speech-to-text engines).
    func readableURL(for path: String) throws -> URL
}

/// Stores the Archive as plain files in a folder.
public struct PlainFolderStorage: ArchiveStorage {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public func read(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }

    public func write(_ data: Data, to path: String) throws {
        let target = try url(path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    public func exists(_ path: String) -> Bool {
        guard let target = try? url(path) else { return false }
        return FileManager.default.fileExists(atPath: target.path)
    }

    public func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: url(path))
    }

    public func importFile(from source: URL, to path: String) throws {
        let target = try url(path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: target)
    }

    public func files(named name: String, under folder: String) throws -> [String] {
        let base = try url(folder)
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
            return []
        }
        let rootComponents = resolvedRoot.pathComponents
        return
            enumerator
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == name }
            .map { $0.resolvingSymlinksInPath().pathComponents.dropFirst(rootComponents.count).joined(separator: "/") }
            .sorted()
    }

    public func readableURL(for path: String) throws -> URL {
        try url(path)
    }

    private var resolvedRoot: URL { root.resolvingSymlinksInPath() }

    /// `resolvingSymlinksInPath()` only works on paths that exist, so resolve the deepest existing
    /// ancestor and re-append the not-yet-existing rest.
    private static func resolvingExistingSymlinks(_ url: URL) -> URL {
        var existing = url
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return rest.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
    }

    /// Resolves `path` inside the Archive, following symlinks, and refuses anything that lands outside it.
    private func url(_ path: String) throws -> URL {
        let rootComponents = resolvedRoot.pathComponents
        let target = Self.resolvingExistingSymlinks(resolvedRoot.appendingPathComponent(path).standardizedFileURL)
        let components = target.pathComponents
        guard components.count > rootComponents.count, components.starts(with: rootComponents) else {
            throw ArchiveStorageError.invalidPath(path)
        }
        return target
    }
}
