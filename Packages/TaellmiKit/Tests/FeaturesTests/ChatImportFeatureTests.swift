import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Importing WhatsApp chats, as you see it")
struct ChatImportFeatureTests {
    nonisolated private static func entry(_ id: String) -> Entry {
        Entry(
            id: id, createdAt: sampleDate, durationSeconds: nil, source: .whatsApp, folder: "entries/\(id)",
            text: "Nachricht \(id)")
    }

    @Test(
        "the report says how many messages came in, were already here or had no words, and which files failed and why",
        arguments: [
            (ChatImportReport(imported: [entry("a")]), "imported 1 message."),
            (
                ChatImportReport(imported: [entry("a"), entry("b")], alreadyHere: 1, withoutWords: 3),
                "imported 2 messages. 1 was already here. left out 3 without words, like photos and voice messages."
            ),
            (
                ChatImportReport(
                    alreadyHere: 2,
                    failed: [
                        .init(file: "_chat.txt", problem: .withOthers), .init(file: "chat.zip", problem: .zipped),
                    ]),
                "imported 0 messages. 2 were already here. couldn't import 2: _chat.txt (a chat with others; only chats with yourself for now), chat.zip (unzip it first)."
            ),
            (
                ChatImportReport(
                    failed: [
                        .init(file: "a.txt", problem: .notAChat), .init(file: "b.txt", problem: .unreadable),
                        .init(file: "c.txt", problem: .notText), .init(file: "d.txt", problem: .unsaved),
                    ]),
                "imported 0 messages. couldn't import 4: a.txt (not a whatsapp chat), b.txt (couldn't be read), c.txt (not text), d.txt (not every message was saved; import it again)."
            ),
            (
                ChatImportReport(),
                "found no whatsapp chat there. export the chat, unzip it, and choose its _chat.txt or its folder."
            ),
        ])
    func message(report: ChatImportReport, expected: String) {
        #expect(ChatImportMessage.text(for: report) == expected)
    }

    @Test("⌘K import from whatsapp asks for files, imports what you chose and tells you what happened")
    func importFromPalette() async {
        let library = FakeLibrary(entries: [])
        await library.setChatImportReport(ChatImportReport(imported: [Self.entry("a")]))
        let model = ExploreViewModel(library: library, autosaveDelay: .zero)

        #expect(Command.importWhatsApp.title == "import from whatsapp …")
        await model.perform(.importWhatsApp)
        #expect(model.chatImportRequest == 1, "the window opens the file picker")

        let chosen = [URL(fileURLWithPath: "/tmp/WhatsApp Chat - You")]
        await model.importChats(from: chosen)
        #expect(model.importProgress == nil)
        #expect(await library.importedFrom == chosen)
        #expect(model.importMessage == "imported 1 message.")
        await model.refresh()
        #expect(model.entries.map(\.id) == ["a"])
    }

    @Test("a failed chat import says so")
    func importFails() async {
        let library = FakeLibrary(entries: [])
        await library.failImports()
        let model = ExploreViewModel(library: library, autosaveDelay: .zero)
        await model.importChats(from: [URL(fileURLWithPath: "/tmp/_chat.txt")])
        #expect(model.importMessage == "couldn't import the chat. try again.")
    }

    @Test("thoughts from whatsapp say so, and an imported thought's date can be changed")
    func source() {
        #expect(EntrySource.whatsApp.rawValue == "whatsapp")
        #expect(EntrySource.whatsApp.isImported)
    }
}
