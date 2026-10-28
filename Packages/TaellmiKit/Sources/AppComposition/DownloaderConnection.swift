import Config
import Darwin
import Downloader
import Foundation
import Synchronization

/// The live fetcher: asks `taellmi-downloader.xpc`, the only part of tällmi that may go online (ADR 0016), to
/// fill a file tällmi opened. macOS starts the downloader for the connection and ends it when it is idle or
/// tällmi quits. tällmi watches the file grow for the progress bars.
nonisolated struct DownloaderConnection: ModelFileFetching {
    let progressInterval: Duration
    private let connect: @Sendable () -> NSXPCConnection

    /// `serviceName`: the downloader's bundle id, tällmi's own plus `.downloader` (`project.yml`).
    init(serviceName: String, progressInterval: Duration) {
        self.init(progressInterval: progressInterval) { NSXPCConnection(serviceName: serviceName) }
    }

    init(progressInterval: Duration, connect: @escaping @Sendable () -> NSXPCConnection) {
        self.progressInterval = progressInterval
        self.connect = connect
    }

    func fetch(_ url: URL, into file: FileHandle, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let connection = connect()
        connection.remoteObjectInterface = NSXPCInterface(with: ModelFileDownloading.self)
        connection.resume()
        defer { connection.invalidate() }
        let interval = progressInterval
        // Ends as soon as it is cancelled, and is awaited before returning: the caller closes the file next, and
        // reading a closed file's descriptor would end the app.
        let watching = Task.detached(priority: .utility) {
            while true {
                do { try await Task.sleep(for: interval) } catch { return }
                progress(Self.size(of: file))
            }
        }
        let answer = Answer()
        // The SDK doesn't mark NSXPCConnection Sendable, but invalidating it from another thread is how a
        // connection is meant to be stopped; nothing else touches it from there.
        nonisolated(unsafe) let stopping = connection
        let result: Result<Void, any Error>
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    answer.wait(with: continuation)
                    let proxy = connection.remoteObjectProxyWithErrorHandler { answer.give(.failure($0)) }
                    guard let downloader = proxy as? any ModelFileDownloading else {
                        answer.give(.failure(CocoaError(.xpcConnectionInvalid)))
                        return
                    }
                    downloader.fetch(url, into: file) { error in
                        answer.give(error.map { .failure($0) } ?? .success(()))
                    }
                }
            } onCancel: {
                stopping.invalidate()
            }
            result = .success(())
        } catch {
            result = .failure(error)
        }
        watching.cancel()
        await watching.value
        try result.get()
        progress(Self.size(of: file))
    }

    // Read with fstat, never by seeking: the downloader writes through the same open file, so moving its
    // position here would move the downloader's.
    private static func size(of file: FileHandle) -> Int64 {
        var info = stat()
        return fstat(file.fileDescriptor, &info) == 0 ? Int64(info.st_size) : 0
    }
}

/// The downloader's answer, given once: its reply and a broken connection may both arrive.
private nonisolated final class Answer: Sendable {
    private let continuation = Mutex<CheckedContinuation<Void, any Error>?>(nil)

    func wait(with continuation: CheckedContinuation<Void, any Error>) {
        self.continuation.withLock { $0 = continuation }
    }

    func give(_ result: Result<Void, any Error>) {
        let waiting = continuation.withLock { current in
            defer { current = nil }
            return current
        }
        waiting?.resume(with: result)
    }
}
