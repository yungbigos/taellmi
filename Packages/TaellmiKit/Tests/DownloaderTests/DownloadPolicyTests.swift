import Downloader
import Foundation
import Testing

@Suite("What the downloader may fetch, and where it may follow")
struct DownloadPolicyTests {
    static let policy = DownloadPolicy(hosts: ["huggingface.co", "hf.co"])
    static let revision = "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"

    @Test(
        "a pinned file from an allowed host is fetched",
        arguments: [
            "https://huggingface.co/kim/sprache/resolve/\(revision)/vocab.json",
            "https://huggingface.co/kim/sprache/resolve/\(revision)/Encoder.mlmodelc/weights/weight.bin",
            "https://hf.co/kim/sprache/resolve/\(revision)/vocab.json",
        ])
    func allows(url: String) throws {
        #expect(Self.policy.allows(try #require(URL(string: url))))
    }

    @Test(
        "anything else is refused before it leaves the mac",
        arguments: [
            "http://huggingface.co/kim/sprache/resolve/\(revision)/vocab.json",  // not encrypted
            "https://example.com/kim/sprache/resolve/\(revision)/vocab.json",  // another host
            "https://huggingface.co.example.com/kim/sprache/resolve/\(revision)/vocab.json",
            "https://us.aws.cdn.hf.co/kim/sprache/resolve/\(revision)/vocab.json",  // only redirects go there
            "https://sam:geheim@huggingface.co/kim/sprache/resolve/\(revision)/vocab.json",
            "https://huggingface.co:8443/kim/sprache/resolve/\(revision)/vocab.json",
            "https://huggingface.co/kim/sprache/resolve/\(revision)/vocab.json?notiz=hallo",
            "https://huggingface.co/kim/sprache/resolve/\(revision)/vocab.json#hallo",
            "https://huggingface.co/kim/sprache/resolve/main/vocab.json",  // not a pinned revision
            "https://huggingface.co/kim/sprache/resolve/7DD20FE6B1797D35F5E3307E8B1732D9A178EDFE/vocab.json",
            "https://huggingface.co/kim/sprache/blob/\(revision)/vocab.json",
            "https://huggingface.co/kim/sprache/resolve/\(revision)",  // no file
            "https://huggingface.co/kim/sprache/resolve/\(revision)/../../../api/whoami",
            "https://huggingface.co/kim/sprache/resolve/\(revision)/%2E%2E/whoami",
            "https://huggingface.co/api/models/kim/sprache",
        ])
    func refuses(url: String) throws {
        #expect(!Self.policy.allows(try #require(URL(string: url))))
    }

    @Test(
        "redirects are followed only over https to the allowed hosts and their subdomains",
        arguments: [
            ("https://us.aws.cdn.hf.co/xet-bridge-us/abc?X-Amz-Signature=123", true),
            ("https://cas-bridge.xethub.hf.co/xet-bridge-us/abc", true),
            ("https://huggingface.co/api/resolve-cache/models/kim/sprache/abc/vocab.json", true),
            ("http://us.aws.cdn.hf.co/xet-bridge-us/abc", false),
            ("https://example.com/abc", false),
            ("https://hf.co.example.com/abc", false),
            ("https://nothf.co/abc", false),
            ("https://sam:geheim@us.aws.cdn.hf.co/abc", false),
            ("https://us.aws.cdn.hf.co:8443/abc", false),
        ])
    func redirects(url: String, allowed: Bool) throws {
        #expect(Self.policy.allowsRedirect(to: try #require(URL(string: url))) == allowed)
    }

    @Test("without allowed hosts nothing is fetched")
    func emptyRefusesAll() throws {
        let url = try #require(URL(string: "https://huggingface.co/kim/sprache/resolve/\(Self.revision)/vocab.json"))
        #expect(!DownloadPolicy(hosts: []).allows(url))
    }
}
