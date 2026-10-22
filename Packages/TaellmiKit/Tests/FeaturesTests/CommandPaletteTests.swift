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
                text: "Termin mit Kim verschieben.")
        ])
        return (ExploreViewModel(library: library, autosaveDelay: .zero), library)
    }

    @Test("with nothing typed it lists every command with its shortcut (formatting only while editing a thought)")
    func listsCommands() async {
        let (explore, _) = makeExplore()
        explore.shortcuts = [.deleteThought: try? Hotkey(parsing: "command+delete")].compactMapValues { $0 }
        let palette = CommandPaletteModel(explore: explore)
        await palette.update(query: "")
        #expect(palette.results.count == Commands.all.filter { !$0.isFormatting }.count)
        #expect(palette.results.contains { $0.title == "delete thought" && $0.shortcut == "⌘⌫" })
    }

    @Test("typing finds matching commands and thoughts together")
    func findsBoth() async {
        let (explore, _) = makeExplore()
        let palette = CommandPaletteModel(explore: explore)
        await palette.update(query: "trash")
        #expect(palette.results.map(\.title).contains("show trash"))
        await palette.update(query: "kim")
        #expect(palette.results.map(\.title) == ["Termin mit Kim verschieben."])
    }

    @Test("choosing a thought opens it; choosing a command runs it")
    func choose() async throws {
        let (explore, _) = makeExplore()
        await explore.refresh()
        let palette = CommandPaletteModel(explore: explore)
        palette.isPresented = true

        await palette.update(query: "kim")
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

        await palette.update(query: "kim")
        await library.releaseHeldSearches()
        await early.value

        #expect(palette.query == "kim")
        #expect(palette.results.map(\.title) == ["Termin mit Kim verschieben."])
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

/// Stands in for a thought editor and records what it was asked to do.
@MainActor
private final class RecordingEditor: FormattingTarget {
    var actions: [FormattingAction] = []
    func applyFormatting(_ action: FormattingAction) { actions.append(action) }
}

@Suite("⌘K formats the thought you were typing in")
struct PaletteFormattingTests {
    private func makePalette() -> (ExploreViewModel, CommandPaletteModel) {
        let explore = ExploreViewModel(library: FakeLibrary(entries: []), autosaveDelay: .zero)
        return (explore, CommandPaletteModel(explore: explore))
    }

    @Test("without a thought being edited, formats are not offered")
    func notWhileNotEditing() async {
        let (explore, palette) = makePalette()
        explore.isPaletteOpen = true
        await palette.update(query: "bold")
        #expect(!palette.results.contains { $0.kind == .command(.formatBold) })
    }

    @Test("while typing in a thought, ⌘K offers the formats and applies the chosen one to that thought")
    func whileEditing() async throws {
        let (explore, palette) = makePalette()
        let editor = RecordingEditor()
        explore.formatting.editorDidFocus(editor)
        explore.isPaletteOpen = true
        explore.formatting.editorDidBlur(editor)

        await palette.update(query: "numbered")
        let item = try #require(palette.results.first { $0.kind == .command(.formatNumberedList) })
        await palette.choose(item)
        #expect(editor.actions == [.toggle(.numberedList)])
    }
}
