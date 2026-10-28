import Foundation
import Synchronization

/// What tällmi asks of `taellmi-downloader.xpc`. The downloader only answers; it can't call tällmi.
@objc public protocol ModelFileDownloading {
    /// Writes the body of `url` into `file`, a file tällmi opened for writing. Replies once, with nil when the
    /// whole body was written.
    func fetch(_ url: URL, into file: FileHandle, reply: @escaping @Sendable ((any Error)?) -> Void)
}

public enum DownloadRefusal: Error, Equatable {
    case notAllowed(URL)
    case redirectNotAllowed(URL)
    case status(Int)
}

/// Fetches pinned files over https into a file it is handed, within `DownloadPolicy`. It keeps nothing: no
/// cookies, cache or passwords, and it can't open files itself (its sandbox has no file access).
public final class FileDownloader: NSObject, ModelFileDownloading, Sendable {
    private let policy: DownloadPolicy
    private let session: URLSession
    private let transfers = Mutex<[Int: URLSessionDataTask]>([:])

    public init(policy: DownloadPolicy, configuration: URLSessionConfiguration = privateConfiguration()) {
        self.policy = policy
        session = URLSession(configuration: configuration)
    }

    /// No cookies, cache or stored credentials: a request carries nothing about you.
    public static func privateConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return configuration
    }

    public func fetch(_ url: URL, into file: FileHandle, reply: @escaping @Sendable ((any Error)?) -> Void) {
        guard policy.allows(url) else {
            reply(DownloadRefusal.notAllowed(url))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let task = session.dataTask(with: request)
        let id = task.taskIdentifier
        task.delegate = Transfer(policy: policy, file: file) { [weak self] error in
            self?.transfers.withLock { _ = $0.removeValue(forKey: id) }
            reply(error)
        }
        transfers.withLock { $0[id] = task }
        task.resume()
    }

    /// tällmi went away: stop everything in flight.
    public func cancelAll() {
        for task in transfers.withLock({ Array($0.values) }) { task.cancel() }
    }
}

/// One file in flight: writes what arrives into the handed-over file and replies once.
private final class Transfer: NSObject, URLSessionDataDelegate, Sendable {
    private let policy: DownloadPolicy
    private let file: FileHandle
    private let reply: Mutex<(@Sendable ((any Error)?) -> Void)?>
    private let failure = Mutex<(any Error)?>(nil)

    init(policy: DownloadPolicy, file: FileHandle, reply: @escaping @Sendable ((any Error)?) -> Void) {
        self.policy = policy
        self.file = file
        self.reply = Mutex(reply)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, policy.allowsRedirect(to: url) else {
            fail(DownloadRefusal.redirectNotAllowed(request.url ?? response.url ?? URL(fileURLWithPath: "/")), task)
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, failure.withLock({ $0 }) == nil else {
            fail(DownloadRefusal.status(status), dataTask)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure.withLock({ $0 }) == nil else { return }
        do {
            try file.write(contentsOf: data)
        } catch {
            fail(error, dataTask)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let result = failure.withLock { $0 } ?? error
        reply.withLock { reply in
            reply?(result)
            reply = nil
        }
    }

    // The first failure is the one reported; the task is stopped so nothing more is written.
    private func fail(_ error: any Error, _ task: URLSessionTask) {
        failure.withLock { if $0 == nil { $0 = error } }
        task.cancel()
    }
}
