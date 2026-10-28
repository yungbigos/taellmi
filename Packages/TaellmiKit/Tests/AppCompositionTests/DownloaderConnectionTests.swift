import Downloader
import Foundation
import Synchronization
import TestSupport
import Testing

@testable import AppComposition

/// Stands in for `taellmi-downloader.xpc` inside the test process: writes a fixed body, or answers with an error.
nonisolated final class FakeDownloaderService: NSObject, ModelFileDownloading, NSXPCListenerDelegate, Sendable {
    let body: Data
    let fails: Bool

    init(body: Data, fails: Bool = false) {
        self.body = body
        self.fails = fails
    }

    func fetch(_ url: URL, into file: FileHandle, reply: @escaping @Sendable ((any Error)?) -> Void) {
        guard !fails else {
            reply(URLError(.badServerResponse))
            return
        }
        do {
            try file.write(contentsOf: body)
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ModelFileDownloading.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

@Suite("tällmi's side of the connection to the downloader")
struct DownloaderConnectionTests {
    static let url = URL(
        string: "https://huggingface.co/kim/sprache/resolve/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe/x")!

    /// A connection to `service` over a real XPC listener in this process.
    private func connect(to service: FakeDownloaderService) -> (DownloaderConnection, NSXPCListener) {
        let listener = NSXPCListener.anonymous()
        listener.delegate = service
        listener.resume()
        let endpoint = listener.endpoint
        let connection = DownloaderConnection(progressInterval: .milliseconds(1)) {
            NSXPCConnection(listenerEndpoint: endpoint)
        }
        return (connection, listener)
    }

    @Test("file after file, the progress reaches each file's size, and nothing reads a file after it is closed")
    func fileAfterFile() async throws {
        let service = FakeDownloaderService(body: Data(repeating: 0xC3, count: 64 * 1024))
        let (connection, listener) = connect(to: service)
        defer { withExtendedLifetime(service) { listener.invalidate() } }
        let temp = try TemporaryDirectory()
        for index in 0..<300 {
            let file = temp.url.appending(path: "\(index).part")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            let seen = Mutex<Int64>(0)
            try await connection.fetch(Self.url, into: handle) { bytes in seen.withLock { $0 = max($0, bytes) } }
            try handle.close()
            #expect(seen.withLock { $0 } == Int64(service.body.count))
        }
    }

    @Test("the downloader's error comes back as an error, and the file can be closed right after")
    func failure() async throws {
        let service = FakeDownloaderService(body: Data(), fails: true)
        let (connection, listener) = connect(to: service)
        defer { withExtendedLifetime(service) { listener.invalidate() } }
        let temp = try TemporaryDirectory()
        for index in 0..<20 {
            let file = temp.url.appending(path: "\(index).part")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            await #expect(throws: (any Error).self) {
                try await connection.fetch(Self.url, into: handle) { _ in }
            }
            try handle.close()
        }
    }
}
