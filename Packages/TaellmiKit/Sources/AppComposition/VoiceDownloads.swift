import Config
import Domain
import Features
import Foundation
import os

/// This launch's download of the voice models: one at a time, in role order (ADR 0016). It belongs to the app,
/// not to a window, so it goes on when the onboarding closes.
final class VoiceDownloads {
    /// A model to download, and its provider's base URL.
    struct Item: Sendable {
        let model: ModelConfig
        let baseURL: URL
    }

    private let downloader: ModelDownloader
    private let onInstalled: () -> Void
    /// Models waiting, downloading or failed in this launch, by model id. Installed ones are read from disk.
    private(set) var states: [String: VoiceModelState] = [:]
    private var running: Task<Void, Never>?
    private var followers: [AsyncStream<Void>.Continuation] = []
    private let logger = Logger(subsystem: "app.taellmi", category: "downloads")

    /// `onInstalled` runs after each model is verified, so waiting work can pick it up.
    init(downloader: ModelDownloader, onInstalled: @escaping () -> Void) {
        self.downloader = downloader
        self.onInstalled = onInstalled
    }

    /// Starts downloading `items` unless a download already runs. Either way, the stream ticks on every change
    /// and ends when the download does.
    func start(_ items: [Item]) -> AsyncStream<Void> {
        let (stream, follower) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        if running == nil {
            guard !items.isEmpty else {
                follower.finish()
                return stream
            }
            for item in items { states[item.model.id] = .waiting }
            running = Task { await run(items) }
        }
        followers.append(follower)
        follower.yield()
        return stream
    }

    private func run(_ items: [Item]) async {
        for item in items {
            let id = item.model.id
            update(id, .downloading(received: 0))
            // Progress arrives off the main actor; only the newest count matters.
            let (progress, report) = AsyncStream<Int64>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let downloader = downloader
            let work = Task.detached(priority: .utility) {
                defer { report.finish() }
                try await downloader.download(item.model, from: item.baseURL) { report.yield($0) }
            }
            for await bytes in progress { update(id, .downloading(received: bytes)) }
            do {
                try await work.value
                update(id, nil)
                onInstalled()
            } catch {
                logger.error("The download of \(id, privacy: .public) stopped: \(String(describing: error))")
                update(id, .failed)
            }
        }
        running = nil
        for follower in followers { follower.finish() }
        followers = []
    }

    private func update(_ id: String, _ state: VoiceModelState?) {
        states[id] = state
        for follower in followers { follower.yield() }
    }
}

/// Stands in for the downloader where there is none (tests that don't download): every fetch fails.
nonisolated struct NoDownloader: ModelFileFetching {
    func fetch(_ url: URL, into file: FileHandle, progress: @escaping @Sendable (Int64) -> Void) async throws {
        throw URLError(.notConnectedToInternet)
    }
}
