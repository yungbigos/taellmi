import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Writing a new thought in the tällmi window")
struct ComposerTests {
    private func makeModel() -> (ExploreViewModel, FakeLibrary) {
        let library = FakeLibrary(entries: [])
        return (ExploreViewModel(library: library, autosaveDelay: .zero), library)
    }

    @Test("new thought opens an empty composer")
    func opens() async {
        let (model, _) = makeModel()
        await model.perform(.newThought)
        #expect(model.isComposing)
        #expect(model.composerText.isEmpty)
    }

    @Test("finishing saves one typed thought with the text and opens it")
    func finish() async throws {
        let (model, library) = makeModel()
        await model.perform(.newThought)
        model.composerText = "Ein Gedanke, ganz in Ruhe aufgeschrieben."
        await model.finishComposing()
        #expect(!model.isComposing)
        let saved = try await library.search(EntryQuery())
        #expect(saved.map(\.text) == ["Ein Gedanke, ganz in Ruhe aufgeschrieben."])
        #expect(saved.first?.source == .typed)
        #expect(model.detail?.entry.id == saved.first?.id)
    }

    @Test("autosave creates the thought once, later saves update the same thought")
    func autosave() async throws {
        let (model, library) = makeModel()
        await model.perform(.newThought)
        model.composerText = "Anfang"
        await model.saveComposerIfNeeded()
        model.composerText = "Anfang und mehr"
        await model.saveComposerIfNeeded()
        await model.finishComposing()
        #expect(try await library.search(EntryQuery()).map(\.text) == ["Anfang und mehr"])
    }

    @Test("an empty composer creates nothing")
    func empty() async throws {
        let (model, library) = makeModel()
        await model.perform(.newThought)
        model.composerText = "   "
        await model.finishComposing()
        #expect(try await library.search(EntryQuery()).isEmpty)
        #expect(!model.isComposing)
    }

}

@Suite("The composer listens like tälli")
struct ListeningComposerTests {
    private func makeModel() throws -> (
        ExploreViewModel, CaptureViewModel, FakeRecorder, FakeJournal, TemporaryDirectory
    ) {
        let temp = try TemporaryDirectory()
        let recorder = FakeRecorder(folder: temp.url)
        let journal = FakeJournal()
        let capture = CaptureViewModel(recorder: recorder, journal: journal)
        let explore = ExploreViewModel(library: FakeLibrary(entries: []), autosaveDelay: .zero, capture: capture)
        return (explore, capture, recorder, journal, temp)
    }

    @Test("opening the composer starts listening")
    func listensOnOpen() async throws {
        let (explore, capture, recorder, _, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        await explore.perform(.newThought)
        #expect(capture.isRecording)
        #expect(await recorder.isRecording)
    }

    @Test("starting to type stops listening and throws the recording away")
    func typingTakesOver() async throws {
        let (explore, capture, recorder, journal, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        await explore.perform(.newThought)
        explore.composerText = "Lieber schreiben."
        await explore.typingStarted()
        #expect(!capture.isRecording)
        #expect(await recorder.cancelled == 1)
        await explore.finishComposing()
        #expect(await journal.added.isEmpty)
    }

    @Test("⌘↩ while listening saves a spoken thought and closes the composer")
    func saveSpoken() async throws {
        let (explore, capture, _, journal, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        await explore.perform(.newThought)
        await explore.finishComposing()
        #expect(await journal.added.count == 1)
        #expect(!capture.isRecording)
        #expect(!explore.isComposing)
    }

    @Test("esc while listening discards the recording and closes the composer")
    func escDiscards() async throws {
        let (explore, capture, recorder, journal, temp) = try makeModel()
        defer { withExtendedLifetime(temp) {} }
        await explore.perform(.newThought)
        await explore.closeComposer()
        #expect(await journal.added.isEmpty)
        #expect(await recorder.cancelled == 1)
        #expect(!capture.isRecording)
        #expect(!explore.isComposing)
    }
}
