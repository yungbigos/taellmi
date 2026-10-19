import Features
import Testing

@Suite("Writing style: normal or all lowercase")
struct AppearanceViewModelTests {
    actor FakeStore: AppearanceStore {
        var value: String
        init(_ value: String) { self.value = value }
        func textCase() async throws -> String { value }
        func setTextCase(_ value: String) async throws { self.value = value }
    }

    @Test("loads the saved choice")
    func loads() async {
        let model = AppearanceViewModel(store: FakeStore("lowercase"))
        await model.load()
        #expect(model.isLowercase)
    }

    @Test("switching saves the choice; unknown saved values fall back to normal")
    func switches() async {
        let store = FakeStore("something-else")
        let model = AppearanceViewModel(store: store)
        await model.load()
        #expect(!model.isLowercase)
        await model.setLowercase(true)
        #expect(await store.value == "lowercase")
        await model.setLowercase(false)
        #expect(await store.value == "normal")
    }

    @Test("only the display changes: the helper lowercases text when the setting is on")
    func display() async {
        let model = AppearanceViewModel(store: FakeStore("lowercase"))
        await model.load()
        #expect(model.display("Heute mit Marleen telefoniert.") == "heute mit marleen telefoniert.")
    }
}
