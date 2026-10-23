import CoreText
import Domain
import SwiftUI
import os

// The soft-eyes wordmark from the brand tokens (docs/brand.md §3): the word in Funnel Display, softened by a
// round-joined outline, in ink, with the ä's two dots pink. The same rules as docs/brand/make_svgs.py.
struct Wordmark: View {
    // The font size, in points.
    var size: CGFloat
    @Environment(\.brand) private var brand
    // Laid out once per brand and size, not on every redraw.
    @State private var shape: Drawing?

    var body: some View {
        Group {
            if let brand, let shape {
                Canvas { context, _ in
                    context.translateBy(x: -shape.bounds.minX, y: -shape.bounds.minY)
                    let ink = brand.color(.ink)
                    context.stroke(
                        shape.letters, with: .color(ink),
                        style: StrokeStyle(
                            lineWidth: brand.wordmark.softenStroke * size, lineCap: .round, lineJoin: .round))
                    context.fill(shape.letters, with: .color(ink))
                    for dot in shape.dots {
                        let box = CGRect(
                            x: dot.center.x - dot.radius, y: dot.center.y - dot.radius, width: dot.radius * 2,
                            height: dot.radius * 2)
                        context.fill(Path(ellipseIn: box), with: .color(brand.color(.pink)))
                    }
                }
                .frame(width: shape.bounds.width, height: shape.bounds.height)
            } else {
                Text("tällmi")
            }
        }
        .accessibilityElement()
        .accessibilityLabel("tällmi")
        .onChange(of: brand, initial: true) { shape = brand.flatMap { Self.shape(tokens: $0.wordmark, size: size) } }
    }

    struct Dot: Equatable {
        var center: CGPoint
        var radius: CGFloat
    }

    // Where the ä's dots go, over the a's outline (y down, before softening).
    static func dots(over a: CGRect, size: CGFloat, tokens: BrandTokens.Wordmark) -> [Dot] {
        let dots = tokens.dots
        let radius = dots.radius * size
        let gap = dots.gap * size
        let centerX = a.midX + dots.offsetX * size
        let centerY = a.minY - dots.lift * size - tokens.softenStroke * size / 2 - radius
        return [-1.0, 1.0].map { Dot(center: CGPoint(x: centerX + $0 * gap / 2, y: centerY), radius: radius) }
    }

    private struct Drawing {
        var letters: Path
        var dots: [Dot]
        var bounds: CGRect
    }

    // The letters (the ä drawn as an a) laid out on a baseline at y 0, y down, and the dots over the a.
    private static func shape(tokens: BrandTokens.Wordmark, size: CGFloat) -> Drawing? {
        let weightAxis = 0x7767_6874  // 'wght'
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [
                kCTFontFamilyNameAttribute: tokens.font,
                kCTFontVariationAttribute: [weightAxis: tokens.weight],
            ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        guard CTFontCopyFamilyName(font) as String == tokens.font else {
            Logger(subsystem: "app.taellmi", category: "Features")
                .error("The wordmark font \(tokens.font, privacy: .public) is missing")
            return nil
        }
        let word = tokens.text.replacingOccurrences(of: "ä", with: "a")
        guard
            let aIndex = tokens.text.firstIndex(of: "ä").map({
                tokens.text.distance(from: tokens.text.startIndex, to: $0)
            })
        else { return nil }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: word, attributes: [.init(kCTFontAttributeName as String): font]))
        var letters = Path()
        var aBounds = CGRect.null
        var index = 0
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: 0)
                if let outline = CTFontCreatePathForGlyph(font, glyph, &flip) {
                    let path = Path(outline)
                    letters.addPath(path)
                    if index == aIndex { aBounds = path.boundingRect }
                }
                index += 1
            }
        }
        guard !aBounds.isNull else { return nil }
        let dots = Self.dots(over: aBounds, size: size, tokens: tokens)
        let soft = tokens.softenStroke * size
        var bounds = letters.boundingRect.insetBy(dx: -soft / 2, dy: -soft / 2)
        for dot in dots {
            bounds = bounds.union(
                CGRect(
                    x: dot.center.x - dot.radius, y: dot.center.y - dot.radius, width: dot.radius * 2,
                    height: dot.radius * 2))
        }
        return Drawing(letters: letters, dots: dots, bounds: bounds)
    }
}
