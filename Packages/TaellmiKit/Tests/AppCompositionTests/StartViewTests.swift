import Config
import Domain
import Features
import Testing

@Suite("The view the tällmi window opens in")
struct StartViewTests {
    @Test("the shipped config opens the window in flow")
    func shippedStartViewIsFlow() throws {
        let setting = try #require(try SeedBundle.bundled().settings.first { $0.key == SettingKeys.exploreStartView })
        guard case .string(let value) = setting.value else {
            Issue.record("start view is not a string")
            return
        }
        #expect(ExploreViewKind(rawValue: value) == .flow)
    }
}
