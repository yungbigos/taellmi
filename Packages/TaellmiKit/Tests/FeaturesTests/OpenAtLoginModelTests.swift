import Features
import Testing

@Suite("open tällmi at login, in settings")
struct OpenAtLoginModelTests {
    @Test("shows whether macOS opens tällmi at login")
    func loads() {
        let model = OpenAtLoginModel(isOn: { true }, set: { $0 })
        model.load()
        #expect(model.isOn)
    }

    @Test("switching it shows what macOS really did")
    func showsWhatMacOSDid() {
        let model = OpenAtLoginModel(isOn: { false }, set: { _ in false })
        model.set(true)
        #expect(!model.isOn)
    }
}
