import CoreGraphics
import Testing

@testable import Features

@Suite("Measuring a thought's height once")
struct MeasuredHeightsTests {
    @Test("the same text at the same width is measured once; a new width or text measures again")
    func cachesByTextAndWidth() {
        var cache = MeasuredHeights()
        var measured = 0
        let measure: () -> CGFloat = {
            measured += 1
            return 40
        }
        #expect(cache.height(text: "Die Heizung gluckert.", width: 600, style: 1, measure: measure) == 40)
        #expect(cache.height(text: "Die Heizung gluckert.", width: 600, style: 1, measure: measure) == 40)
        #expect(measured == 1)
        _ = cache.height(text: "Die Heizung gluckert.", width: 400, style: 1, measure: measure)
        _ = cache.height(text: "Die Heizung gluckert wieder.", width: 400, style: 1, measure: measure)
        _ = cache.height(text: "Die Heizung gluckert wieder.", width: 400, style: 2, measure: measure)
        #expect(measured == 4)
    }

    @Test("only a few recent sizes are kept, so a long scroll doesn't grow memory")
    func bounded() {
        var cache = MeasuredHeights(limit: 3)
        for width in 1...10 { _ = cache.height(text: "x", width: CGFloat(width), style: 0) { 10 } }
        #expect(cache.count <= 3)
    }
}
