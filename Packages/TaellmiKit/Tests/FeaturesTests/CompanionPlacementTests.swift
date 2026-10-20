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

@Suite("Moving tälli by dragging it")
struct CompanionDragTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let start = CGRect(x: 400, y: 300, width: 300, height: 160)

    @Test("the panel moves by exactly as far as you dragged")
    func movesWithTheDrag() {
        let moved = CompanionPlacement.dragged(start, by: CGVector(dx: 120, dy: -40), screen: screen)
        #expect(moved.origin == CGPoint(x: 520, y: 260))
        #expect(moved.size == start.size)
    }

    @Test(
        "you can't drag it off the screen",
        arguments: [
            CGVector(dx: 5000, dy: 0), CGVector(dx: -5000, dy: 0), CGVector(dx: 0, dy: 5000),
            CGVector(dx: 0, dy: -5000),
        ])
    func staysOnScreen(drag: CGVector) {
        #expect(screen.contains(CompanionPlacement.dragged(start, by: drag, screen: screen)))
    }

    @Test("a press that barely moves is a poke; moving further is a drag", arguments: [(3.0, false), (10.0, true)])
    func pokeOrDrag(distance: Double, isDrag: Bool) {
        let start = CGPoint(x: 500, y: 500)
        let end = CGPoint(x: 500 + distance * 0.6, y: 500 + distance * 0.8)
        #expect(CompanionPlacement.isDrag(from: start, to: end, tolerance: 4) == isDrag)
    }

    private let size = CGSize(width: 300, height: 160)

    @Test("where you dropped tälli is where it comes back, if that spot is still on a screen")
    func comesBackWhereDropped() {
        let frame = CompanionPlacement.remembered(CGPoint(x: 300, y: 200), size: size, screens: [screen])
        #expect(frame?.origin == CGPoint(x: 300, y: 200))
    }

    @Test("a remembered spot no screen shows any more (display unplugged) is forgotten")
    func forgetsOffScreenSpot() {
        #expect(CompanionPlacement.remembered(CGPoint(x: 3000, y: 200), size: size, screens: [screen]) == nil)
        #expect(CompanionPlacement.remembered(nil, size: size, screens: [screen]) == nil)
    }

    @Test("the remembered spot is stored and read back as text in config")
    func storesAsText() {
        #expect(CompanionPlacement.encode(CGPoint(x: 300.5, y: 200)) == "300.5,200.0")
        #expect(CompanionPlacement.decode("300.5,200.0") == CGPoint(x: 300.5, y: 200))
        #expect(CompanionPlacement.decode("") == nil)
    }
}
