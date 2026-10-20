import CoreText
import Domain
import SwiftUI
import os

/// tälli, the one and only drawing of the character (ADR 0009): the softened Funnel Display "a" as its
/// body, the two pink dots as its eyes, the a's lower counter as its mouth. Every screen uses this view, so a
/// new look is a change here and in the brand tokens only. Behaviour lives in `TalliMotion`.
public struct TalliView: View {
    var mood: TalliMood
    var entrance: TalliEntrance?
    @Environment(\.brand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var renderer: TalliRenderer?

    /// - Parameter entrance: how tälli comes alive when it appears; `nil` to be there already.
    public init(mood: TalliMood, entrance: TalliEntrance? = .rise) {
        self.mood = mood
        self.entrance = entrance
    }

    public var body: some View {
        // Under Reduce Motion the face is still; a slow tick keeps the dots' brightness and letters current.
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.2 : nil)) { context in
            Canvas { canvas, size in
                guard let renderer else { return }
                let now = context.date.timeIntervalSinceReferenceDate
                let hour =
                    Double(Calendar.current.component(.hour, from: context.date))
                    + Double(Calendar.current.component(.minute, from: context.date)) / 60
                let pose = renderer.motion.pose(mood: mood, at: now, reduceMotion: reduceMotion, hour: hour)
                renderer.draw(pose, in: &canvas, size: size, dark: colorScheme == .dark)
            }
        }
        .onChange(of: brand, initial: true) {
            renderer = brand.map { TalliRenderer(tokens: $0, entrance: entrance) }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch mood {
        case .idle: "tälli"
        case .listening: "tälli is listening"
        case .thinking: "tälli is thinking"
        case .saved: "tälli, saved"
        }
    }
}

/// Turns a pose into pixels. Holds the glyph outlines and the motion state for one visible tälli.
@MainActor
final class TalliRenderer {
    let motion: TalliMotion
    private let tokens: BrandTokens
    private var glyphs: [Character: Glyph] = [:]
    private let font: CTFont

    struct Glyph {
        /// Outline at 1 pt, y down, baseline at 0.
        var path: Path
        var bounds: CGRect
        var advance: CGFloat
    }

    init(tokens: BrandTokens, entrance: TalliEntrance?) {
        self.tokens = tokens
        motion = TalliMotion(tokens: tokens, entrance: entrance, random: { Double.random(in: 0...1) })
        let weightAxis = 0x7767_6874  // 'wght'
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [
                kCTFontFamilyNameAttribute: tokens.talli.glyph.font,
                kCTFontVariationAttribute: [weightAxis: tokens.talli.glyph.weight],
            ] as CFDictionary)
        font = CTFontCreateWithFontDescriptor(descriptor, 1, nil)
        // Core Text silently substitutes a missing family, which would give tälli the wrong body.
        let family = CTFontCopyFamilyName(font) as String
        if family != tokens.talli.glyph.font {
            Logger(subsystem: "app.taellmi", category: "Features")
                .error(
                    "tälli's font \(tokens.talli.glyph.font, privacy: .public) is missing; using \(family, privacy: .public)"
                )
        }
    }

    private func glyph(_ character: Character) -> Glyph {
        if let cached = glyphs[character] { return cached }
        var units = Array(String(character).utf16)
        var ids = [CGGlyph](repeating: 0, count: units.count)
        CTFontGetGlyphsForCharacters(font, &units, &ids, units.count)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &ids, &advance, 1)
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        let outline = CTFontCreatePathForGlyph(font, ids[0], &flip) ?? CGMutablePath()
        let made = Glyph(path: Path(outline), bounds: outline.boundingBoxOfPath, advance: advance.width)
        glyphs[character] = made
        return made
    }

    func draw(_ pose: TalliPose, in canvas: inout GraphicsContext, size: CGSize, dark: Bool) {
        let talli = tokens.talli
        let a = glyph(Character(talli.glyph.char))
        let letterScale = talli.letters.size
        let lettersWidth = pose.letters.reduce(0.0) {
            $0 + Double(glyph($1.character).advance) * letterScale * $1.opacity
        }
        // Size: the ä plus its eyes fit the height; the letters may use the room on the right.
        let layout = talli.layout
        let em = min(size.height / layout.fitHeight, size.width / (layout.fitWidth + lettersWidth)) * layout.fill
        let center = CGPoint(
            x: size.width / 2 - CGFloat(lettersWidth) * em / 2 + pose.offset.width * em,
            y: size.height * layout.centerY + pose.offset.height * em)

        var layer = canvas
        layer.opacity = pose.opacity
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .radians(pose.rotation))
        layer.scaleBy(x: pose.scale * em, y: pose.scale * pose.squash * em)

        // Glyph space: the a's bounding box is centred on the origin.
        let box = a.bounds
        let origin = CGPoint(x: -box.midX, y: -box.midY)
        layer.drawLayer { body in
            fillSoftened(a, at: origin, in: &body)
            var x = origin.x + a.advance
            for letter in pose.letters {
                let shape = glyph(letter.character)
                var copy = body
                copy.opacity = letter.opacity
                copy.translateBy(x: x, y: origin.y)
                copy.scaleBy(x: letterScale, y: letterScale)
                fillSoftened(shape, at: .zero, in: &copy)
                x += shape.advance * letterScale * letter.opacity
            }
            if pose.mouth > 0.02 {
                let mouth = talli.mouth
                let width = box.width * mouth.rx * (1 + (mouth.openRx - 1) * pose.mouth)
                let height = box.height * mouth.ry * (1 + (mouth.openRy - 1) * pose.mouth)
                let mouthCenter = CGPoint(
                    x: origin.x + box.minX + box.width * mouth.center[0], y: origin.y + box.height * mouth.center[1])
                body.blendMode = .destinationOut
                body.opacity = pose.mouth
                body.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: mouthCenter.x - width, y: mouthCenter.y - height, width: width * 2, height: height * 2)),
                    with: .color(.black))
            }
        }

        // The eyes: always two solid pink dots.
        let eyes = talli.eyes
        let pink = BrandTokens.cgColor(hex: dark ? tokens.color.dark.pink.value : tokens.color.light.pink.value)
        let radius = eyes.radius * pose.dotScale
        let top = box.minY - box.midY - eyes.xheightPad - eyes.liftAboveXheight
        layer.opacity = pose.opacity * pose.dotOpacity
        for (index, side) in [-1.0, 1.0].enumerated() {
            let x = eyes.offsetX + side * eyes.gap / 2 + pose.eyes.dx * eyes.travelX
            let y = top + pose.eyes.dy * eyes.travelY
            if index == 0 && pose.brow > 0.01 {
                let brow = talli.brow
                let spread = brow.spread * pose.brow
                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: x, y: y + eyes.radius * brow.lift * pose.brow),
                    radius: eyes.radius * brow.length * pose.brow,
                    startAngle: .radians(.pi * (1.5 - spread)), endAngle: .radians(.pi * (1.5 + spread)),
                    clockwise: false)
                layer.stroke(
                    arc, with: .color(pink),
                    style: StrokeStyle(lineWidth: eyes.radius * 2 * (1 - brow.thinning * pose.brow), lineCap: .round))
                continue
            }
            let height = max(0.004, radius * (1 - pose.lid))
            layer.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - height, width: radius * 2, height: height * 2)),
                with: .color(pink))
        }
    }

    /// Fills a glyph softened (inflated by a round-joined outline) in the body material: the gradient plus
    /// its soft light overlays, never brighter than a tint.
    private func fillSoftened(_ shape: Glyph, at origin: CGPoint, in context: inout GraphicsContext) {
        let body = tokens.talli.body
        // A solid mask first (outline plus its round-joined stroke), then the material painted only onto it.
        // This way overlapping contours of the variable font leave no seams, and the light reaches the rim.
        let path = shape.path.offsetBy(dx: origin.x, dy: origin.y)
        let soften = tokens.talli.glyph.softenStroke
        let box = shape.bounds.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -soften / 2, dy: -soften / 2)
        let everywhere = Path(box.insetBy(dx: -box.width, dy: -box.height))
        let point = { (fraction: [Double]) in
            CGPoint(x: box.minX + box.width * fraction[0], y: box.minY + box.height * fraction[1])
        }
        let gradient = Gradient(
            stops: body.fill.stops.map { .init(color: BrandTokens.cgColor(hex: $0.color), location: $0.at) })
        context.drawLayer { layer in
            layer.fill(path, with: .color(.black))
            layer.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: soften, lineJoin: .round))
            layer.blendMode = .sourceAtop
            layer.fill(
                everywhere,
                with: .linearGradient(gradient, startPoint: point(body.fill.from), endPoint: point(body.fill.to)))
            for overlay in body.overlays {
                let colour = BrandTokens.cgColor(hex: overlay.color, opacity: overlay.opacity)
                layer.fill(
                    everywhere,
                    with: .radialGradient(
                        Gradient(colors: [colour, colour.opacity(0)]), center: point(overlay.center), startRadius: 0,
                        endRadius: overlay.radius))
            }
        }
    }
}
