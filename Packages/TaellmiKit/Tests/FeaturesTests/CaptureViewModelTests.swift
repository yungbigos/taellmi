import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Capture from the menu bar")
struct CaptureViewModelTests {
    private func makeModel(startError: CaptureError? = nil) throws -> (
        CaptureViewModel, FakeRecorder, FakeJournal, TemporaryDirectory
    ) {
        let temp = try TemporaryDirectory()
        let recorder = FakeRecorder(folder: temp.url, startError: startError)
        let journal = FakeJournal()
        return (CaptureViewModel(recorder: recorder, journal: journal), recorder, journal, temp)
    }

    @Test("toggling once starts recording")
    func startsRecording() async throws {
        let (model, recorder, _, _) = try makeModel()
        await model.toggle()
        #expect(model.isRecording)
        #expect(await recorder.isRecording)
    }

    @Test("toggling again stops and saves the recording as a new Entry")
    func stopsAndSaves() async throws {
        let (model, _, journal, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        await model.toggle()
        await model.toggle()
        #expect(!model.isRecording)
        #expect(await journal.added.count == 1)
        #expect(model.errorMessage == nil)
    }

    @Test("pressing the hotkey twice quickly does not start twice or show a false error")
    func doublePressIsIgnored() async throws {
        let (model, recorder, _, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        async let first: Void = model.toggle()
        async let second: Void = model.toggle()
        _ = await (first, second)
        #expect(model.isRecording)
        #expect(await recorder.isRecording)
        #expect(model.errorMessage == nil)
    }

    @Test("while recording, the live preview shows what is heard; after stopping it is cleared")
    func livePreview() async throws {
        let temp = try TemporaryDirectory()
        let chunk = AudioSamples(samples: [0, 0.1], sampleRate: 16_000)
        let model = CaptureViewModel(
            recorder: FakeRecorder(folder: temp.url, liveChunks: [chunk, chunk]), journal: FakeJournal(),
            preview: FakeLivePreview())
        await model.toggle()
        try await waitUntil { model.livePreviewText == "Gehört: 2 …" }
        await model.toggle()
        #expect(model.livePreviewText.isEmpty)
    }

    @Test("a live preview that fails does not stop the recording")
    func failingPreview() async throws {
        let temp = try TemporaryDirectory()
        let journal = FakeJournal()
        let model = CaptureViewModel(
            recorder: FakeRecorder(folder: temp.url), journal: journal, preview: FakeLivePreview(fails: true))
        await model.toggle()
        #expect(model.isRecording)
        await model.toggle()
        #expect(await journal.added.count == 1)
        #expect(model.errorMessage == nil)
    }

    @Test("Esc cancels: the recording is thrown away and no Entry is made")
    func cancel() async throws {
        let (model, recorder, journal, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        await model.toggle()
        await model.cancel()
        #expect(!model.isRecording)
        #expect(await recorder.isRecording == false)
        #expect(await recorder.cancelled == 1)
        #expect(await journal.added.isEmpty)
    }

    @Test("typing instead of talking saves a typed Entry and ends a running recording without saving it")
    func typedEntry() async throws {
        let (model, recorder, journal, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        await model.toggle()
        model.typedText = "  Marleen anrufen.  "
        await model.submitTyped()
        #expect(!model.isRecording)
        #expect(await recorder.cancelled == 1)
        #expect(await journal.typed == ["Marleen anrufen."])
        #expect(await journal.added.isEmpty)
        #expect(model.typedText.isEmpty)
        #expect(model.lastSavedAt != nil)
    }

    @Test("blank typed text saves nothing")
    func blankTyped() async throws {
        let (model, _, journal, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        model.typedText = "   "
        await model.submitTyped()
        #expect(await journal.typed.isEmpty)
    }

    @Test("saving a recording marks when it was saved, for the short confirmation")
    func savedMarker() async throws {
        let (model, _, _, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        #expect(model.lastSavedAt == nil)
        await model.toggle()
        await model.toggle()
        #expect(model.lastSavedAt != nil)
    }

    @Test("a denied microphone shows an explanation instead of recording")
    func microphoneDenied() async throws {
        let (model, _, _, _) = try makeModel(startError: .microphoneDenied)
        await model.toggle()
        #expect(!model.isRecording)
        #expect(model.errorMessage?.contains("Mikrofon") == true)
    }

    @Test("recent Entries update live, including when a Transcript arrives")
    func liveEntries() async throws {
        let (model, _, journal, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        model.startObservingEntries()
        await model.toggle()
        await model.toggle()
        await journal.complete("entry-1", text: "Ich war heute im Büro.")

        try await waitUntil { model.recentEntries.first?.text == "Ich war heute im Büro." }
        #expect(model.recentEntries.count == 1)
    }

    @Test("an Entry without Text yet is shown as being transcribed")
    func previewText() {
        let pending = Entry(id: "a", createdAt: sampleDate, durationSeconds: 3, source: .voice, folder: "x")
        var done = pending
        done.text = "Ein ziemlich langer Gedanke über die Arbeit, der weit mehr als achtzig Zeichen hat, honestly."
        #expect(CaptureViewModel.preview(of: pending) == "Wird transkribiert …")
        #expect(CaptureViewModel.preview(of: done).count <= 81)
        #expect(CaptureViewModel.preview(of: done).hasSuffix("…"))
    }
}

/// Polls a main-actor condition until it holds, failing after a short timeout.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("condition not met within \(timeout)")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
