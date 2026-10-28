import Config
import CryptoKit
import Foundation
import Synchronization

/// Serves model files from memory as if downloaded, by their full URL, and records what was asked for.
public final class FakeModelFetcher: ModelFileFetching, Sendable {
    private let files: [String: Data]
    private let requests = Mutex<[URL]>([])

    public init(files: [String: Data]) {
        self.files = files
    }

    /// Every URL fetched, in order.
    public var requested: [URL] { requests.withLock { $0 } }

    public func fetch(_ url: URL, into file: FileHandle, progress: @escaping @Sendable (Int64) -> Void) async throws {
        requests.withLock { $0.append(url) }
        guard let data = files[url.absoluteString] else { throw URLError(.fileDoesNotExist) }
        // In two halves, so progress is seen on the way.
        let half = data.count / 2
        try file.write(contentsOf: data.prefix(half))
        progress(Int64(half))
        try file.write(contentsOf: data.dropFirst(half))
        progress(Int64(data.count))
    }
}

/// The lowercase hex SHA-256 of `data`, as model configs pin it.
public func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
