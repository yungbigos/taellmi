import Downloader
import Foundation

// taellmi-downloader.xpc: the only part of tällmi that may go online (ADR 0016). macOS starts it when tällmi asks
// (the download button) and ends it when idle or when tällmi quits. It may only fetch the pinned files its
// Info.plist's hosts allow, into files tällmi hands it; it can open no files itself.
final class Listener: NSObject, NSXPCListenerDelegate {
    private let policy = DownloadPolicy(bundle: .main)

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let downloader = FileDownloader(policy: policy)
        connection.exportedInterface = NSXPCInterface(with: ModelFileDownloading.self)
        connection.exportedObject = downloader
        // tällmi went away or cancelled: stop what it asked for.
        connection.invalidationHandler = { downloader.cancelAll() }
        connection.resume()
        return true
    }
}

let delegate = Listener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
