import CryptoKit
import Domain
import Foundation

/// Fetches one file over the network into a file tällmi opened. Only the downloader may go online
/// (ADR 0016); tällmi hands it the open file and checks what it wrote.
public protocol ModelFileFetching: Sendable {
    /// Writes the body of `url` into `file`; `progress` gets the bytes written so far.
    func fetch(_ url: URL, into file: FileHandle, progress: @escaping @Sendable (Int64) -> Void) async throws
}

public enum ModelDownloadError: Error, Equatable {
    /// The model has no pinned revision, no source or no listed files.
    case notDownloadable(String)
    /// A file path that would land outside the model's folder.
    case unsafePath(String)
    /// A downloaded file whose size or SHA-256 differs from its config.
    case mismatch(String)
}

/// Downloads a model's pinned files, checks each against its size and SHA-256, and marks the model verified,
/// as `scripts/download-model.sh` does. The fetcher is never trusted: only files that match are kept.
public struct ModelDownloader: Sendable {
    private let installation: ModelInstallation
    private let fetcher: any ModelFileFetching

    public init(installation: ModelInstallation, fetcher: any ModelFileFetching) {
        self.installation = installation
        self.fetcher = fetcher
    }

    /// Fetches what is missing from `baseURL` (the provider's), e.g. `https://huggingface.co`.
    /// `progress` gets the model's bytes on this Mac so far.
    public func download(
        _ model: ModelConfig, from baseURL: URL, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        guard let revision = model.revision, let repo = model.sourceRef, !model.files.isEmpty else {
            throw ModelDownloadError.notDownloadable(model.id)
        }
        if let unsafe = model.files.first(where: { !Self.isSafe($0.path) }) {
            throw ModelDownloadError.unsafePath(unsafe.path)
        }
        let folder = installation.directory(for: model)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Files are about to change: until all of them match again, the model doesn't count as here.
        try installation.removeMark(model)
        var done: Int64 = 0
        for file in model.files {
            try Task.checkCancellation()
            let target = folder.appending(path: file.path)
            if !(try Self.matches(target, file)) {
                let url = baseURL.appending(path: repo).appending(path: "resolve").appending(path: revision)
                    .appending(path: file.path)
                try await fetch(url, to: target, checkedAgainst: file) { [done] bytes in progress(done + bytes) }
            }
            done += Int64(file.bytes)
            progress(done)
        }
        try installation.markVerified(model)
    }

    // Into `<file>.part` first. Then tällmi takes its own copy (a clone on APFS, so it costs nothing) and checks
    // that: the downloader may still hold the `.part` open, but never the copy. Only a copy that matches its size
    // and SHA-256 stays.
    private func fetch(
        _ url: URL, to target: URL, checkedAgainst file: ModelFile, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let files = FileManager.default
        try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = target.appendingPathExtension("part")
        guard files.createFile(atPath: part.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: part.path])
        }
        defer { try? files.removeItem(at: part) }
        let handle = try FileHandle(forWritingTo: part)
        do {
            try await fetcher.fetch(url, into: handle, progress: progress)
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
        try files.copyItem(at: part, to: target)
        guard try Self.matches(target, file) else {
            try? files.removeItem(at: target)
            throw ModelDownloadError.mismatch(file.path)
        }
    }

    /// A relative path that stays inside the model's folder.
    static func isSafe(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Whether `url` holds exactly the pinned file: its size first, then its SHA-256.
    static func matches(_ url: URL, _ file: ModelFile) throws -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == file.bytes else {
            return false
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return hex == file.sha256.lowercased()
    }
}
