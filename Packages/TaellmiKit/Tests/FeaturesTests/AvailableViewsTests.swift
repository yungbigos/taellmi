import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Which views the window offers (config)")
struct AvailableViewsTests {
    private func model(start: ExploreViewKind) -> ExploreViewModel {
        ExploreViewModel(
            library: FakeLibrary(entries: []), autosaveDelay: .zero, startView: start,
            availableViews: [.stack, .flow, .space])
    }

    @Test("a hidden view is never shown: its command does nothing and it isn't offered")
    func hidden() async {
        let model = model(start: .flow)
        await model.perform(.showTime)
        #expect(model.view == .flow)
        #expect(!model.isAvailable(.showTime))
        #expect(model.isAvailable(.showFlow))
        #expect(model.availableViews == [.stack, .flow, .space])
    }

    @Test("a start view that is hidden falls back to the first one offered")
    func startFallsBack() {
        #expect(model(start: .time).view == .stack)
    }
}
