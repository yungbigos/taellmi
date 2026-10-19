import CoreGraphics
import Features
import Testing

@Suite("Where tälli appears")
struct CompanionPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 300, height: 160)

    @Test("appears just below and to the right of the cursor")
    func besideCursor() {
        let frame = CompanionPlacement.frame(cursor: CGPoint(x: 400, y: 500), size: size, screen: screen, offset: 20)
        #expect(frame.origin == CGPoint(x: 420, y: 320))
    }

    @Test(
        "stays fully on screen near every edge",
        arguments: [CGPoint(x: 1430, y: 500), CGPoint(x: 5, y: 10), CGPoint(x: 1435, y: 895), CGPoint(x: 700, y: 50)])
    func staysOnScreen(cursor: CGPoint) {
        let frame = CompanionPlacement.frame(cursor: cursor, size: size, screen: screen, offset: 20)
        #expect(screen.contains(frame))
    }

    @Test("near the right edge it flips to the left of the cursor instead of covering it")
    func flipsLeft() {
        let frame = CompanionPlacement.frame(cursor: CGPoint(x: 1400, y: 500), size: size, screen: screen, offset: 20)
        #expect(frame.maxX <= 1380)
    }
}

@Suite("tälli gliding after the cursor")
struct CompanionFollowTests {
    @Test("each frame moves a fraction of the way towards the target")
    func movesFraction() {
        let next = CompanionFollow.step(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 40), smoothing: 0.25)
        #expect(next == CGPoint(x: 25, y: 10))
    }

    @Test("snaps onto the target when it is less than a pixel away, so it comes to rest")
    func snaps() {
        let target = CGPoint(x: 100, y: 100)
        #expect(CompanionFollow.step(from: CGPoint(x: 99.6, y: 100.3), to: target, smoothing: 0.25) == target)
    }

    @Test("smoothing 1 jumps straight to the target; 0 is treated as 'no following'")
    func extremes() {
        let target = CGPoint(x: 50, y: 60)
        #expect(CompanionFollow.step(from: .zero, to: target, smoothing: 1) == target)
        #expect(CompanionFollow.step(from: .zero, to: target, smoothing: 0) == .zero)
    }
}
