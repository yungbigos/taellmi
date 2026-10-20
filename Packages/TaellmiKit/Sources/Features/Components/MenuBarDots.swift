import AppKit
import Domain

/// The menu bar icon: tälli's two dots. Quiet, they follow the menu bar like any system icon; while
/// listening they turn pink, the one place colour says "it hears you".
public enum MenuBarDots {
    public static func image(listening: Bool, tokens: BrandTokens?) -> NSImage {
        // Without tokens the config is broken; show a neutral system glyph rather than invent values.
        guard let tokens else {
            return NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "tällmi") ?? NSImage()
        }
        let eyes = tokens.talli.eyes
        // The dots keep their logo proportions: radius and gap relative to the glyph size.
        let size = NSSize(width: tokens.menuBar.sizePt, height: tokens.menuBar.sizePt)
        let em = size.height * tokens.menuBar.em
        let radius = eyes.radius * em
        let gap = eyes.gap * em
        let pink = BrandTokens.nsColor(hex: tokens.color.dark.pink.value)
        let image = NSImage(size: size, flipped: false) { rect in
            (listening ? pink : .black).setFill()
            for side in [-1.0, 1.0] {
                let center = NSPoint(x: rect.midX + side * gap / 2, y: rect.midY)
                NSBezierPath(
                    ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                ).fill()
            }
            return true
        }
        image.isTemplate = !listening
        image.accessibilityDescription = "tällmi"
        return image
    }
}
