import Downloader
import Foundation
import Synchronization
import Testing

/// Answers requests from memory instead of the network, and records every request that reached it.
final class StubProtocol: URLProtocol {
    enum Answer: Sendable {
        case body(status: Int, Data)
        case redirect(to: URL)
        /// Starts the answer and never finishes it, like a stalled connection.
        case stall
    }

    static let answers = Mutex<[String: Answer]>([:])
    static let seen = Mutex<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.withLock { $0.append(request) }
        guard let url = request.url, let answer = Self.answers.withLock({ $0[url.absoluteString] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        switch answer {
        case .body(let status, let data):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: nil)
            if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target):
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/2", headerFields: ["Location": target.absoluteString])
            if let response {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            }
            client?.urlProtocolDidFinishLoading(self)
        case .stall:
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/2", headerFields: nil)
            if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        }
    }

    override func stopLoading() {}

    static func reached(_ url: URL) -> Bool {
        seen.withLock { $0.contains { $0.url == url } }
    }
}

@Suite("The downloader writes pinned files into the file it is handed")
struct FileDownloaderTests {
    static let policy = DownloadPolicy(hosts: ["huggingface.co", "hf.co"])

    /// A unique URL per test, so tests running side by side don't share answers.
    static func fileURL(_ name: String = UUID().uuidString) -> URL {
        URL(string: "https://huggingface.co/kim/sprache/resolve/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe/\(name)")!
    }

    static func downloader() -> FileDownloader {
        let configuration = FileDownloader.privateConfiguration()
        configuration.protocolClasses = [StubProtocol.self]
        return FileDownloader(policy: policy, configuration: configuration)
    }

    /// Runs one fetch into a fresh temporary file; returns what was written and the error, if any.
    static func fetch(_ url: URL) async throws -> (Data, (any Error)?) {
        let file = FileManager.default.temporaryDirectory.appending(path: "taellmi-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        let downloader = downloader()
        let error: (any Error)? = await withCheckedContinuation { continuation in
            downloader.fetch(url, into: handle) { continuation.resume(returning: $0) }
        }
        try? handle.close()
        return (try Data(contentsOf: file), error)
    }

    @Test("a pinned file's bytes end up in the file, and nothing about you is sent")
    func writesBody() async throws {
        let url = Self.fileURL("vocab.json")
        let body = Data(#"{"tokens": ["Straße", "Grüße", "meeting"]}"#.utf8)
        StubProtocol.answers.withLock { $0[url.absoluteString] = .body(status: 200, body) }

        let (written, error) = try await Self.fetch(url)

        #expect(error == nil)
        #expect(written == body)
        let request = try #require(StubProtocol.seen.withLock { $0.first { $0.url == url } })
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Hugging Face's redirect to its download servers is followed")
    func followsRedirect() async throws {
        let url = Self.fileURL()
        let cdn = try #require(URL(string: "https://us.aws.cdn.hf.co/xet-bridge-us/\(UUID().uuidString)?sig=1"))
        let body = Data("Gewichte für die Spracherkennung".utf8)
        StubProtocol.answers.withLock {
            $0[url.absoluteString] = .redirect(to: cdn)
            $0[cdn.absoluteString] = .body(status: 200, body)
        }

        let (written, error) = try await Self.fetch(url)

        #expect(error == nil)
        #expect(written == body)
    }

    @Test("a request outside the rules never leaves the mac")
    func refusesBeforeSending() async throws {
        let url = try #require(URL(string: "https://example.com/kim/sprache/resolve/main/\(UUID().uuidString)"))
        StubProtocol.answers.withLock { $0[url.absoluteString] = .body(status: 200, Data("nope".utf8)) }

        let (written, error) = try await Self.fetch(url)

        #expect(error != nil)
        #expect(written.isEmpty)
        #expect(!StubProtocol.reached(url))
    }

    @Test("a redirect away from the allowed hosts stops the download, and nothing is written")
    func refusesRedirect() async throws {
        let url = Self.fileURL()
        let elsewhere = try #require(URL(string: "https://example.com/\(UUID().uuidString)"))
        StubProtocol.answers.withLock {
            $0[url.absoluteString] = .redirect(to: elsewhere)
            $0[elsewhere.absoluteString] = .body(status: 200, Data("von woanders".utf8))
        }

        let (written, error) = try await Self.fetch(url)

        #expect(error != nil)
        #expect(written.isEmpty)
        #expect(!StubProtocol.reached(elsewhere))
    }

    @Test("an answer that isn't the file (e.g. not found) is an error, and its page isn't written")
    func refusesErrorStatus() async throws {
        let url = Self.fileURL()
        StubProtocol.answers.withLock { $0[url.absoluteString] = .body(status: 404, Data("Entry not found".utf8)) }

        let (written, error) = try await Self.fetch(url)

        #expect(error != nil)
        #expect(written.isEmpty)
    }

    @Test("when tällmi goes away, what it asked for stops, with an error")
    func cancelAll() async throws {
        let url = Self.fileURL()
        StubProtocol.answers.withLock { $0[url.absoluteString] = .stall }
        let file = FileManager.default.temporaryDirectory.appending(path: "taellmi-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let downloader = Self.downloader()

        let error: (any Error)? = await withCheckedContinuation { continuation in
            downloader.fetch(url, into: handle) { continuation.resume(returning: $0) }
            Task {
                let deadline = ContinuousClock.now + .seconds(2)
                while !StubProtocol.reached(url), ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                downloader.cancelAll()
            }
        }

        #expect(StubProtocol.reached(url))
        #expect(error != nil)
    }

    @Test("the downloader keeps no cookies, cache or passwords")
    func privateConfiguration() {
        let configuration = FileDownloader.privateConfiguration()
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
    }
}
