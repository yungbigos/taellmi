import Domain
import Foundation

/// A recorder that pretends to record and hands back a file in a temporary folder.
public actor FakeRecorder: AudioRecording {
    public private(set) var isRecording = false
    private let folder: URL
    private let startError: CaptureError?
    private var startedAt: Date?

    public init(folder: URL, startError: CaptureError? = nil) {
        self.folder = folder
        self.startError = startError
    }

    public func start() async throws {
        if let startError { throw startError }
        guard !isRecording else { throw CaptureError.alreadyRecording }
        isRecording = true
        startedAt = sampleDate
    }

    public func stop() async throws -> Recording {
        guard isRecording, let startedAt else { throw CaptureError.notRecording }
        isRecording = false
        let file = folder.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data("fake audio".utf8).write(to: file)
        return Recording(file: file, durationSeconds: 4.2, startedAt: startedAt)
    }

    public func level() async -> Float { isRecording ? 0.5 : 0 }
}

/// An in-memory Journal.
public actor FakeJournal: Journal {
    public private(set) var added: [Recording] = []
    private var entries: [Entry] = []
    private var continuations: [AsyncStream<[Entry]>.Continuation] = []
    public nonisolated let archiveFolder = URL(fileURLWithPath: "/tmp/taellmi-fake-archive")

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public func addVoiceEntry(_ recording: Recording) async throws -> Entry {
        added.append(recording)
        let entry = Entry(
            id: "entry-\(added.count)", createdAt: recording.startedAt, durationSeconds: recording.durationSeconds,
            source: .voice, folder: "entries/\(added.count)")
        entries.insert(entry, at: 0)
        publish()
        return entry
    }

    /// Simulates the pipeline finishing a Transcript.
    public func complete(_ id: String, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].text = text
        publish()
    }

    public func recentEntries(limit: Int) async throws -> [Entry] { Array(entries.prefix(limit)) }

    public nonisolated func recentEntryUpdates(limit: Int) -> AsyncStream<[Entry]> {
        AsyncStream { continuation in
            Task { await self.subscribe(continuation, limit: limit) }
        }
    }

    private func subscribe(_ continuation: AsyncStream<[Entry]>.Continuation, limit: Int) {
        continuations.append(continuation)
        continuation.yield(Array(entries.prefix(limit)))
    }

    private func publish() {
        for continuation in continuations { continuation.yield(entries) }
    }
}
