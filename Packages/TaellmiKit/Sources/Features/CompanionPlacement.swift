import CoreGraphics

/// Where tälli's panel goes: beside the cursor when you call it, never covering it, always fully on screen.
/// After that it stays put unless you drag tälli.
/// Coordinates are AppKit screen coordinates (origin bottom-left).
public enum CompanionPlacement {
    public nonisolated static func frame(cursor: CGPoint, size: CGSize, screen: CGRect, offset: CGFloat) -> CGRect {
        var x = cursor.x + offset
        if x + size.width > screen.maxX { x = cursor.x - offset - size.width }
        var y = cursor.y - offset - size.height
        if y < screen.minY { y = cursor.y + offset }
        x = min(max(x, screen.minX), screen.maxX - size.width)
        y = min(max(y, screen.minY), screen.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Whether a press on tälli that moved from `start` to `end` is a drag rather than a poke.
    public nonisolated static func isDrag(from start: CGPoint, to end: CGPoint, tolerance: CGFloat) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > tolerance
    }

    /// The panel after you dragged tälli by `drag` from where it was at the start of the drag; never off screen.
    public nonisolated static func dragged(_ start: CGRect, by drag: CGVector, screen: CGRect) -> CGRect {
        let x = min(max(start.minX + drag.dx, screen.minX), screen.maxX - start.width)
        let y = min(max(start.minY + drag.dy, screen.minY), screen.maxY - start.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: start.size)
    }
}
