import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("⌘K: search or run a command")
struct CommandPaletteTests {
    private func makeExplore() -> (ExploreViewModel, FakeLibrary) {
        let library = FakeLibrary(entries: [
            Entry(
                id: "a", createdAt: sampleDate, durationSeconds: nil, source: .voice, folder: "entries/a",
                text: "Termin mit Marleen verschieben.")
        ])
        return (ExploreViewModel(library: library, autosaveDelay: .zero), library)
    }

    @Test("with nothing typed it lists every command with its shortcut")
    func listsCommands() async {
        let (explore, _) = makeExplore()
        explore.shortcuts = [.deleteThought: try? Hotkey(parsing: "command+delete")].compactMapValues { $0 }
        let palette = CommandPaletteModel(explore: explore)
        await palette.update(query: "")
        #expect(palette.results.count == Commands.all.count)
        #expect(palette.results.contains { $0.title == "delete thought" && $0.shortcut == "⌘⌫" })
    }

    @Test("typing finds matching commands and thoughts together")
    func findsBoth() async {
        let (explore, _) = makeExplore()
        let palette = CommandPaletteModel(explore: explore)
        await palette.update(query: "trash")
        #expect(palette.results.map(\.title).contains("show trash"))
        await palette.update(query: "marleen")
        #expect(palette.results.map(\.title) == ["Termin mit Marleen verschieben."])
    }

    @Test("choosing a thought opens it; choosing a command runs it")
    func choose() async throws {
        let (explore, _) = makeExplore()
        await explore.refresh()
        let palette = CommandPaletteModel(explore: explore)
        palette.isPresented = true

        await palette.update(query: "marleen")
        await palette.choose(try #require(palette.results.first))
        #expect(explore.detail?.entry.id == "a")
        #expect(!palette.isPresented)

        await palette.update(query: "show trash")
        await palette.choose(try #require(palette.results.first))
        #expect(explore.showsTrash)
    }

    @Test("arrow keys move the highlight and stay within the results")
    func highlight() async {
        let (explore, _) = makeExplore()
        let palette = CommandPaletteModel(explore: explore)
        await palette.update(query: "")
        palette.moveHighlight(by: -1)
        #expect(palette.highlighted == 0)
        palette.moveHighlight(by: 100)
        #expect(palette.highlighted == palette.results.count - 1)
    }

    @Test("a slow search for earlier typing never replaces the results for what is typed now")
    func staleSearchIsIgnored() async {
        let (explore, library) = makeExplore()
        let palette = CommandPaletteModel(explore: explore)
        await library.holdSearches(for: "x")
        let early = Task { await palette.update(query: "x") }
        await library.waitUntilASearchIsHeld()

        await palette.update(query: "marleen")
        await library.releaseHeldSearches()
        await early.value

        #expect(palette.query == "marleen")
        #expect(palette.results.map(\.title) == ["Termin mit Marleen verschieben."])
    }
}

@Suite("Running commands in Explore")
struct ExploreCommandTests {
    @Test("delete thought trashes the open one")
    func perform() async {
        let library = FakeLibrary(entries: [
            Entry(id: "a", createdAt: sampleDate, durationSeconds: nil, source: .typed, folder: "entries/a", text: "x")
        ])
        let explore = ExploreViewModel(library: library, autosaveDelay: .zero)
        await explore.refresh()
        await explore.select("a")

        await explore.perform(.deleteThought)

        #expect(explore.entries.isEmpty)
    }

    @Test("a shortcut used by another command counts as a clash")
    func inAppClash() throws {
        let checker = CommandShortcutChecker(
            shortcuts: [
                .openPalette: try Hotkey(parsing: "command+k"), .searchThoughts: try Hotkey(parsing: "command+f"),
            ],
            ignoring: .searchThoughts)
        #expect(checker.conflict(for: try Hotkey(parsing: "command+k")) == "\"search or run a command\"")
        #expect(checker.conflict(for: try Hotkey(parsing: "command+f")) == nil)
    }

}
