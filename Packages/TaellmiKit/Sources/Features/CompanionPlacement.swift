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

/// tälli glides after the cursor: every frame it covers a fraction (`smoothing`, 0…1) of the remaining way.
public enum CompanionFollow {
    public nonisolated static func step(from current: CGPoint, to target: CGPoint, smoothing: CGFloat) -> CGPoint {
        let dx = target.x - current.x
        let dy = target.y - current.y
        if abs(dx) < 1, abs(dy) < 1 { return target }
        let fraction = min(max(smoothing, 0), 1)
        return CGPoint(x: current.x + dx * fraction, y: current.y + dy * fraction)
    }
}
