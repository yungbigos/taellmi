import CoreGraphics

/// Where tälli's panel goes: beside the cursor, never covering it, always fully on screen.
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
}
