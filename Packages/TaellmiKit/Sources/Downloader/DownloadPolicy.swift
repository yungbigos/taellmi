import Foundation

/// What the downloader may fetch (ADR 0016): GET `https://<host>/<owner>/<repo>/resolve/<commit>/<file>` from an
/// allowed host, pinned to a 40-character commit, and redirects only over https to an allowed host or its
/// subdomains (Hugging Face's download servers). Everything else is refused before a byte leaves the Mac.
public struct DownloadPolicy: Sendable {
    /// The `Info.plist` key that lists the allowed hosts; the release check reads the same list.
    public static let hostsKey = "TaellmiAllowedHosts"

    public let hosts: [String]

    public init(hosts: [String]) {
        self.hosts = hosts.map { $0.lowercased() }
    }

    /// The hosts in the downloader's own `Info.plist`; none if the key is missing.
    public init(bundle: Bundle) {
        self.init(hosts: bundle.object(forInfoDictionaryKey: Self.hostsKey) as? [String] ?? [])
    }

    public func allows(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), Self.isPlainHTTPS(parts),
            parts.query == nil, parts.fragment == nil, let host = parts.host?.lowercased(), hosts.contains(host)
        else { return false }
        // "/", owner, repo, "resolve", commit, then the file's path.
        let path = url.pathComponents
        guard path.count >= 6, path[3] == "resolve", Self.isCommit(path[4]) else { return false }
        return !path.dropFirst().contains { $0 == "." || $0 == ".." }
    }

    public func allowsRedirect(to url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), Self.isPlainHTTPS(parts),
            let host = parts.host?.lowercased()
        else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func isPlainHTTPS(_ parts: URLComponents) -> Bool {
        parts.scheme?.lowercased() == "https" && parts.user == nil && parts.password == nil && parts.port == nil
    }

    private static func isCommit(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}
