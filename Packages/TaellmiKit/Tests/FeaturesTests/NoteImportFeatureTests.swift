import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Importing notes, as you see it")
struct NoteImportFeatureTests {
    nonisolated private static func entry(_ id: String) -> Entry {
        Entry(
            id: id, createdAt: sampleDate, durationSeconds: nil, source: .appleNotes, folder: "entries/\(id)",
            text: "# Notiz \(id)")
    }

    @Test(
        "the report says how many notes came in, were already here, or failed and why",
        arguments: [
            (NoteImportReport(imported: [entry("a")]), "imported 1 note."),
            (
                NoteImportReport(imported: [entry("a"), entry("b")], alreadyHere: ["x.md"]),
                "imported 2 notes. 1 was already here."
            ),
            (
                NoteImportReport(
                    alreadyHere: ["x.md", "y.md"],
                    failed: [.init(file: "leer.md", problem: .empty), .init(file: "foto.png", problem: .notANote)]),
                "imported 0 notes. 2 were already here. couldn't import 2: leer.md (no words in it), foto.png (not a note file)."
            ),
            (
                NoteImportReport(
                    failed: [
                        .init(file: "a.md", problem: .unreadable), .init(file: "b.md", problem: .notText),
                    ]),
                "imported 0 notes. couldn't import 2: a.md (couldn't be read), b.md (not text)."
            ),
            (
                NoteImportReport(chats: ChatImportReport(imported: [entry("m"), entry("n")], withoutWords: 3)),
                "imported 2 messages. left out 3 without words, like photos and voice messages."
            ),
            (
                NoteImportReport(imported: [entry("a")], chats: ChatImportReport(imported: [entry("m")])),
                "imported 1 note. imported 1 message."
            ),
            (NoteImportReport(), "found no notes there. choose notes exported from apple notes, or a folder of them."),
        ])
    func message(report: NoteImportReport, expected: String) {
        #expect(NoteImportMessage.text(for: report) == expected)
    }

    @Test("⌘K import asks for files, imports what you chose and tells you what happened")
    func importFromPalette() async {
        let library = FakeLibrary(entries: [])
        await library.setImportReport(NoteImportReport(imported: [Self.entry("a")]))
        let model = ExploreViewModel(library: library, autosaveDelay: .zero)

        await model.perform(.importNotes)
        #expect(model.noteImportRequest == 1, "the window opens the file picker")

        let chosen = [URL(fileURLWithPath: "/tmp/notes")]
        await model.importNotes(from: chosen)
        #expect(model.importProgress == nil)
        #expect(await library.importedFrom == chosen)
        #expect(model.importMessage == "imported 1 note.")
        await model.refresh()
        #expect(model.entries.map(\.id) == ["a"])
    }

    @Test("a failed import says so")
    func importFails() async {
        let library = FakeLibrary(entries: [])
        await library.failImports()
        let model = ExploreViewModel(library: library, autosaveDelay: .zero)
        await model.importNotes(from: [URL(fileURLWithPath: "/tmp/notes")])
        #expect(model.importMessage == "couldn't import the notes. try again.")
    }

    @Test("an imported thought can be given the date you wrote it; spoken and typed thoughts keep theirs")
    func changeDate() async throws {
        let spoken = Entry(
            id: "s", createdAt: sampleDate.addingTimeInterval(-3600), durationSeconds: 4, source: .voice,
            folder: "entries/s", text: "Gesprochen.")
        let library = FakeLibrary(entries: [Self.entry("a"), spoken])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero)
        await model.refresh()
        #expect(model.entries.map(\.id) == ["a", "s"])

        await model.select("s")
        #expect(!model.canChangeDate)
        await model.select("a")
        #expect(model.canChangeDate)

        let written = sampleDate.addingTimeInterval(-86_400 * 200)
        await model.changeDate(to: written)

        #expect(model.detail?.entry.createdAt == written)
        #expect(model.entries.map(\.id) == ["s", "a"], "the list is in the new order")
        #expect(model.errorMessage == nil)
    }

    @Test("in flow, an imported thought's date can be changed too; a spoken one's can't")
    func changeDateInFlow() async throws {
        let spoken = Entry(
            id: "s", createdAt: sampleDate.addingTimeInterval(-3600), durationSeconds: 4, source: .voice,
            folder: "entries/s", text: "Gesprochen.")
        let library = FakeLibrary(entries: [Self.entry("a"), spoken])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .flow)
        await model.refresh()
        #expect(model.flowEntries.map(\.id) == ["a", "s"], "newest first")

        let written = sampleDate.addingTimeInterval(-86_400 * 200)
        await model.changeDate(of: "a", to: written)
        await model.changeDate(of: "s", to: written)

        #expect(model.flowEntries.map(\.id) == ["s", "a"], "the imported thought moved back in time")
        #expect(model.flowEntries.first { $0.id == "s" }?.createdAt == sampleDate.addingTimeInterval(-3600))
    }
}
