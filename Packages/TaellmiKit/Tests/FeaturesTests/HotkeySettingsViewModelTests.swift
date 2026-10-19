import Domain
import Features
import Testing

@Suite("Choosing the tälli hotkey in Settings")
struct HotkeySettingsViewModelTests {
    actor FakeStore: HotkeyStore {
        var saved: String
        init(_ saved: String) { self.saved = saved }
        func current() async throws -> String { saved }
        func save(_ value: String) async throws { saved = value }
    }

    struct FakeChecker: HotkeyConflictChecking {
        var taken: [String]
        func conflict(for hotkey: Hotkey) -> String? {
            taken.contains(hotkey.settingValue) ? "a macOS shortcut (e.g. Spotlight)" : nil
        }
    }

    @Test("shows the current hotkey and warns when macOS already uses it")
    func warnsOnLoad() async throws {
        let model = HotkeySettingsViewModel(
            store: FakeStore("option+command+space"), checker: FakeChecker(taken: ["option+command+space"]))
        await model.load()
        #expect(model.label == "⌥⌘ space")
        #expect(model.warning?.contains("Spotlight") == true)
    }

    @Test("a free combination is saved at once and applied")
    func savesFree() async throws {
        let store = FakeStore("option+command+space")
        var applied: [String] = []
        let model = HotkeySettingsViewModel(store: store, checker: FakeChecker(taken: [])) {
            applied.append($0.settingValue)
        }
        await model.load()
        await model.record(Hotkey(key: .letter("t"), modifiers: [.control, .option]))
        #expect(await store.saved == "control+option+t")
        #expect(applied == ["control+option+t"])
        #expect(model.warning == nil)
    }

    @Test("a taken combination is not saved until you confirm it anyway")
    func confirmsTaken() async throws {
        let store = FakeStore("control+option+t")
        let model = HotkeySettingsViewModel(store: store, checker: FakeChecker(taken: ["option+command+space"]))
        await model.load()
        await model.record(try Hotkey(parsing: "option+command+space"))
        #expect(await store.saved == "control+option+t")
        #expect(model.pendingConflict != nil)
        await model.confirmPending()
        #expect(await store.saved == "option+command+space")
        #expect(model.pendingConflict == nil)
    }
}
