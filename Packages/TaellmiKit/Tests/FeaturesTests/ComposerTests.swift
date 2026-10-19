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
