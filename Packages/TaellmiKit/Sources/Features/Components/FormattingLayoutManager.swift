import AppKit

/// What the thought editor draws in place of hidden markup (ADR 0014), in the text view's own measures.
nonisolated struct FormattingDecorations {
    struct Marker {
        /// Where the item's words start in the Text. Not the line start: hidden markup there has no place of
        /// its own and may sit at the end of the line above.
        var anchor: Int
        /// How far in from the text's left edge the bullet or box sits.
        var indent: CGFloat
    }

    struct Placeholder {
        var text: String
        var font: NSFont
        var color: NSColor
    }

    var hidden = IndexSet()
    var bullets: [Marker] = []
    var boxes: [(marker: Marker, checked: Bool)] = []
    /// Character ranges of quote lines, which get a thin bar at the left.
    var quotes: [NSRange] = []
    var placeholders: [Int: Placeholder] = [:]
    var bulletColor: NSColor = .secondaryLabelColor
    var boxColor: NSColor = .secondaryLabelColor
    var tickColor: NSColor = .controlAccentColor
    var tickMarkColor: NSColor = .white
    var quoteBarWidth: CGFloat = 0
}

/// TextKit 1 layout for the thought editor: hides markup by turning its glyphs into null glyphs, gives a
/// missing image's placeholder its width, and draws bullets, checkboxes and quote bars. The characters
/// themselves never change, so the Text stays exactly what you typed.
nonisolated final class FormattingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var decorations = FormattingDecorations()

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    /// Replaces what is hidden and drawn, and lays the text out again where it changed.
    @MainActor
    func update(_ new: FormattingDecorations, length: Int) {
        let glyphsChanged = new.hidden != decorations.hidden || new.placeholders.keys != decorations.placeholders.keys
        decorations = new
        let all = NSRange(location: 0, length: length)
        if glyphsChanged {
            invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
        }
        invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
        for container in textContainers { container.textView?.needsDisplay = true }
    }

    // MARK: Hiding markup

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont, forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !decorations.hidden.isEmpty || !decorations.placeholders.isEmpty else { return 0 }
        var properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var changed = false
        for index in 0..<glyphRange.length {
            let character = charIndexes[index]
            if decorations.placeholders[character] != nil {
                properties[index] = .controlCharacter
                changed = true
            } else if decorations.hidden.contains(character) {
                properties[index] = .null
                changed = true
            }
        }
        guard changed else { return 0 }
        properties.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            setGlyphs(glyphs, properties: base, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        decorations.placeholders[charIndex] != nil ? .whitespace : action
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        guard let placeholder = decorations.placeholders[charIndex] else { return .zero }
        let width = (placeholder.text as NSString).size(withAttributes: [.font: placeholder.font]).width
        return NSRect(x: glyphPosition.x, y: 0, width: width, height: proposedRect.height)
    }

    // MARK: Drawing

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        decorations.bulletColor.setFill()
        for quote in decorations.quotes {
            let glyphs = glyphRange(forCharacterRange: quote, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphs, glyphsToShow).length > 0 else { continue }
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                NSRect(
                    x: origin.x + rect.minX, y: origin.y + rect.minY, width: self.decorations.quoteBarWidth,
                    height: rect.height
                )
                .fill()
            }
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        for bullet in decorations.bullets {
            guard let place = baseline(ofLineAt: bullet.anchor, within: glyphsToShow), let font = place.font else {
                continue
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: decorations.bulletColor]
            let x = origin.x + place.lineRect.minX + bullet.indent
            ("•" as NSString).draw(
                at: NSPoint(x: x, y: origin.y + place.lineRect.minY + place.baseline - font.ascender),
                withAttributes: attributes)
        }
        for box in decorations.boxes {
            guard let rect = boxRect(for: box.marker, origin: origin, within: glyphsToShow) else { continue }
            // The system's own checkbox symbols, in the brand's colours.
            let name = box.checked ? "checkmark.square.fill" : "square"
            let colors = box.checked ? [decorations.tickMarkColor, decorations.tickColor] : [decorations.boxColor]
            guard
                let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: colors))
            else { continue }
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        for (character, placeholder) in decorations.placeholders {
            let glyph = glyphIndexForCharacter(at: character)
            guard NSLocationInRange(glyph, glyphsToShow) else { continue }
            let lineRect = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = location(forGlyphAt: glyph)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: placeholder.font, .foregroundColor: placeholder.color,
            ]
            (placeholder.text as NSString).draw(
                at: NSPoint(
                    x: origin.x + lineRect.minX + location.x,
                    y: origin.y + lineRect.minY + location.y - placeholder.font.ascender),
                withAttributes: attributes)
        }
    }

    /// The checkbox of a checklist item, in text-container coordinates (add the container's origin).
    func boxRect(forAnchor anchor: Int) -> NSRect? {
        guard let box = decorations.boxes.first(where: { $0.marker.anchor == anchor }) else { return nil }
        return boxRect(for: box.marker, origin: .zero, within: nil)
    }

    /// Where each checkbox's item starts, to find the one that was clicked.
    var boxAnchors: [Int] { decorations.boxes.map(\.marker.anchor) }

    private func boxRect(for marker: FormattingDecorations.Marker, origin: NSPoint, within glyphs: NSRange?) -> NSRect?
    {
        guard let place = baseline(ofLineAt: marker.anchor, within: glyphs), let font = place.font else {
            return nil
        }
        let side = font.capHeight
        return NSRect(
            x: origin.x + place.lineRect.minX + marker.indent,
            y: origin.y + place.lineRect.minY + place.baseline - side, width: side, height: side)
    }

    /// Where the line fragment holding `character` sits, and the font at that character.
    private func baseline(ofLineAt character: Int, within glyphs: NSRange?)
        -> (lineRect: NSRect, baseline: CGFloat, font: NSFont?)?
    {
        guard let storage = textStorage, character <= storage.length, numberOfGlyphs > 0 else { return nil }
        let glyph = min(glyphIndexForCharacter(at: character), numberOfGlyphs - 1)
        if let glyphs, !NSLocationInRange(glyph, glyphs) { return nil }
        let lineRect = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = location(forGlyphAt: glyph).y
        let font =
            character < storage.length ? storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont : nil
        return (lineRect, baseline, font)
    }
}
