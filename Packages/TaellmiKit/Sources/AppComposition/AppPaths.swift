import Foundation

/// Where the app keeps its things. The Archive location becomes configurable in a later phase (ADR 0004).
nonisolated public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Containers/app.taellmi/Data/Library/Application Support/taellmi` when sandboxed.
    public static func live() throws -> AppPaths {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AppPaths(root: support.appendingPathComponent("taellmi", isDirectory: true))
    }

    public var archive: URL { root.appendingPathComponent("Archive", isDirectory: true) }
    public var database: URL { root.appendingPathComponent("taellmi.sqlite") }
    public var models: URL { root.appendingPathComponent("models", isDirectory: true) }
    public var scratch: URL { root.appendingPathComponent("Scratch", isDirectory: true) }
}
