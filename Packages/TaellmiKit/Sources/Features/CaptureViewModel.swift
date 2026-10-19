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

    @ObservationIgnored private let recorder: any AudioRecording
    @ObservationIgnored private let journal: any Journal
    @ObservationIgnored private var observation: Task<Void, Never>?
    /// True while a start or stop is in flight, so a quick second press is ignored.
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private let logger = Logger(subsystem: "app.taellmi", category: "capture")

    public init(recorder: any AudioRecording, journal: any Journal) {
        self.recorder = recorder
        self.journal = journal
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
        guard !text.isEmpty else { return "Wird transkribiert …" }
        guard text.count > maxLength else { return text }
        return text.prefix(maxLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func start() async {
        do {
            try await recorder.start()
            isRecording = true
            recordingStartedAt = Date()
        } catch CaptureError.microphoneDenied {
            errorMessage = "Kein Zugriff aufs Mikrofon. Erlaube tällmi den Zugriff in den Systemeinstellungen."
        } catch {
            logger.error("Could not start recording: \(String(describing: error))")
            errorMessage = "Aufnahme konnte nicht starten."
        }
    }

    private func stopAndSave() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let recording = try await recorder.stop()
            isRecording = false
            recordingStartedAt = nil
            _ = try await journal.addVoiceEntry(recording)
        } catch {
            isRecording = false
            recordingStartedAt = nil
            logger.error("Could not save recording: \(String(describing: error))")
            errorMessage = "Aufnahme konnte nicht gespeichert werden."
        }
    }
}
