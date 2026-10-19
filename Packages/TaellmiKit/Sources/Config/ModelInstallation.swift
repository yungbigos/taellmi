import Domain
import Foundation

/// Where model files live on disk and whether a model's pinned revision has been downloaded and verified.
///
/// The downloader writes a marker file after checking every file's SHA-256; the app only trusts that marker.
public struct ModelInstallation: Sendable {
    static let markerName = ".taellmi-verified"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func directory(for model: ModelConfig) -> URL {
        root.appendingPathComponent(model.id, isDirectory: true)
    }

    public func isInstalled(_ model: ModelConfig) -> Bool {
        let marker = directory(for: model).appendingPathComponent(Self.markerName)
        guard let content = try? String(contentsOf: marker, encoding: .utf8) else { return false }
        return content.trimmingCharacters(in: .whitespacesAndNewlines) == Self.markerContent(for: model)
    }

    /// Records that the model's files were verified. Called by the downloader (and tests).
    public func markVerified(_ model: ModelConfig) throws {
        let folder = directory(for: model)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.markerContent(for: model).write(
            to: folder.appendingPathComponent(Self.markerName), atomically: true, encoding: .utf8)
    }

    private static func markerContent(for model: ModelConfig) -> String {
        model.revision ?? "unversioned"
    }
}
