import Domain
import Foundation
import Observation
import os

/// State and actions behind the menu-bar capture UI.
@Observable
public final class CaptureViewModel {
    public private(set) var isRecording = false
    public private(set) var recordingStartedAt: Date?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var recentEntries: [Entry] = []
    /// What the live preview hears while recording. Throwaway; the Entry's Text comes from the real Transcript.
    public private(set) var livePreviewText = ""
    /// Microphone level 0…1 while recording, for tälli's animation.
    public private(set) var level: Float = 0
    /// When the last Entry was saved, so tälli can confirm briefly.
    public private(set) var lastSavedAt: Date?
    /// The Entry saved last, so tälli's confirmation can open it.
    public private(set) var lastSavedEntryID: String?
    /// Text typed into tälli instead of talking.
    public var typedText = ""

    @ObservationIgnored private let recorder: any AudioRecording
    @ObservationIgnored private let journal: any Journal
    @ObservationIgnored private let preview: (any LivePreviewing)?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    @ObservationIgnored private var observation: Task<Void, Never>?
    /// True while a start or stop is in flight, so a quick second press is ignored.
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private let logger = Logger(subsystem: "app.taellmi", category: "capture")

    public init(recorder: any AudioRecording, journal: any Journal, preview: (any LivePreviewing)? = nil) {
        self.recorder = recorder
        self.journal = journal
        self.preview = preview
    }

    public var archiveFolder: URL { journal.archiveFolder }

    /// Starts recording, or stops and saves the current recording as a new Entry.
    public func toggle() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        if isRecording {
            await stopAndSave()
        } else {
            await start()
        }
    }

    /// Esc: stops and throws the recording away.
    public func cancel() async {
        guard isRecording, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await recorder.cancel()
        isRecording = false
        recordingStartedAt = nil
        stopPreview()
    }

    /// Saves what was typed as a typed Entry. A running recording is thrown away, since you chose to write.
    public func submitTyped() async {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        if isRecording { await cancel() }
        isBusy = true
        defer { isBusy = false }
        do {
            lastSavedEntryID = try await journal.addTypedEntry(text).id
            typedText = ""
            lastSavedAt = Date()
        } catch {
            logger.error("Could not save typed entry: \(String(describing: error))")
            errorMessage = "couldn't save the thought. your text is still here, so try again."
        }
    }

    public func startObservingEntries(limit: Int = 8) {
        observation?.cancel()
        let updates = journal.recentEntryUpdates(limit: limit)
        observation = Task { [weak self] in
            for await entries in updates {
                self?.recentEntries = Array(entries.prefix(limit))
            }
        }
    }

    /// The short line shown for an Entry in the menu.
    public nonisolated static func preview(of entry: Entry, maxLength: Int = 80) -> String {
        let text = entry.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "transcribing …" }
        guard text.count > maxLength else { return text }
        return text.prefix(maxLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func start() async {
        do {
            try await recorder.start()
            isRecording = true
            recordingStartedAt = Date()
            await startPreview()
        } catch CaptureError.microphoneDenied {
            errorMessage = "i can't hear you. allow the microphone in System Settings."
        } catch {
            logger.error("Could not start recording: \(String(describing: error))")
            errorMessage = "couldn't start recording. try again."
        }
    }

    /// Starts the live preview if one is configured, and level metering. Neither can affect the recording.
    private func startPreview() async {
        let recorder = recorder
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                let level = await recorder.level()
                self?.level = level
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let preview else { return }
        let audio = await recorder.liveAudio()
        let logger = logger
        previewTask = Task { [weak self] in
            do {
                for try await update in try await preview.preview(audio) {
                    self?.livePreviewText = update.text
                }
            } catch {
                logger.error("Live preview unavailable: \(String(describing: error))")
            }
        }
    }

    private func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        livePreviewText = ""
        levelTask?.cancel()
        levelTask = nil
        level = 0
    }

    private func stopAndSave() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let recording = try await recorder.stop()
            isRecording = false
            recordingStartedAt = nil
            stopPreview()
            lastSavedEntryID = try await journal.addVoiceEntry(recording).id
            lastSavedAt = Date()
        } catch {
            isRecording = false
            recordingStartedAt = nil
            stopPreview()
            logger.error("Could not save recording: \(String(describing: error))")
            errorMessage = "couldn't save the recording. try again."
        }
    }
}
