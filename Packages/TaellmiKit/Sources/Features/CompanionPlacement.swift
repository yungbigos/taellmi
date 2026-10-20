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

    /// Where you last dropped tälli, if the panel would still be fully on one of the screens.
    public nonisolated static func remembered(_ origin: CGPoint?, size: CGSize, screens: [CGRect]) -> CGRect? {
        guard let origin else { return nil }
        let frame = CGRect(origin: origin, size: size)
        return screens.contains { $0.contains(frame) } ? frame : nil
    }

    /// The remembered spot as config text, "x,y".
    public nonisolated static func encode(_ origin: CGPoint) -> String { "\(Double(origin.x)),\(Double(origin.y))" }

    public nonisolated static func decode(_ text: String) -> CGPoint? {
        let parts = text.split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }
}
