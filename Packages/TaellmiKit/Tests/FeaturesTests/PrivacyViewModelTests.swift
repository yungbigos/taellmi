import Domain
import Features
import Foundation
import Testing

@Suite("Privacy settings")
struct PrivacyViewModelTests {
    actor FakePrivacy: PrivacySettings {
        var moved: URL?
        var locked = false
        func locationDescription() async -> String { "Library" }
        func moveArchive(toParent parent: URL) async throws { moved = parent }
        func exportPlain(to folder: URL) async throws -> Int { 3 }
        func isWindowLocked() async -> Bool { locked }
        func setWindowLocked(_ on: Bool) async throws { locked = on }
        func pendingRecoveryKey() async -> String? { nil }
        var importedFrom: [URL] = []
        func importNotes(from urls: [URL]) async throws -> NoteImportReport {
            importedFrom = urls
            return NoteImportReport(alreadyHere: ["getting active.md"])
        }
    }

    @Test("moving the Archive restarts tällmi afterwards; export reports how many thoughts were written")
    func moveAndExport() async {
        let privacy = FakePrivacy()
        var restarts = 0
        let model = PrivacyViewModel(settings: privacy) { restarts += 1 }
        await model.load()
        #expect(model.location == "Library")
        await model.moveArchive(toParent: URL(fileURLWithPath: "/tmp/elsewhere"))
        #expect(await privacy.moved?.path == "/tmp/elsewhere")
        #expect(restarts == 1)
        await model.export(to: URL(fileURLWithPath: "/tmp/export"))
        #expect(model.message == "exported 3 thoughts.")
    }

    @Test("the Touch ID lock is a setting")
    func lock() async {
        let privacy = FakePrivacy()
        let model = PrivacyViewModel(settings: privacy) {}
        await model.setLocked(true)
        #expect(await privacy.locked)
        #expect(model.isLocked)
    }

    @Test("importing notes from settings tells you what happened")
    func importNotes() async {
        let privacy = FakePrivacy()
        let model = PrivacyViewModel(settings: privacy) {}
        await model.importNotes(from: [URL(fileURLWithPath: "/tmp/notes")])
        #expect(await privacy.importedFrom.map(\.path) == ["/tmp/notes"])
        #expect(model.message == "imported 0 notes. 1 was already here.")
    }
}
