import AppKit
import Domain
import SwiftUI

/// A thought as read mode shows it: styled exactly like the editor (the same FormattingStyler), with the
/// markup left out and bullets and boxes written in. Laid out as plain text, so a long flow scrolls and jumps
/// without building an editor per thought; only the thought you click into becomes the editor.
@MainActor
enum ReadingText {
    static func make(text: String, highlights: [TextHighlight], brand: BrandTokens, token: String)
        -> NSAttributedString
    {
        let storage = NSTextStorage(string: text)
        let formatting = TextFormatting(text)
        let styler = FormattingStyler(brand: brand, token: token)
        let decorations = styler.apply(
            to: storage, formatting: formatting, visibility: formatting.visibility(selection: nil))
        let length = storage.length
        for highlight in highlights where highlight.range.lowerBound >= 0 && highlight.range.upperBound <= length {
            let range = NSRange(location: highlight.range.lowerBound, length: highlight.range.count)
            switch highlight.kind {
            case .concept:
                guard let color = brand.nsFill(.concept, increaseContrast: false) else { continue }
                storage.addAttributes(
                    [.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: color], range: range)
            case .word:
                if let color = brand.nsFill(.matchCurrent, increaseContrast: false) {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                }
            case .passage:
                if let color = brand.nsFill(.related, increaseContrast: false) {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                }
            }
        }
        // Bullets and boxes sit in the indent before the item's words, where the editor draws them: the line
        // starts at the marker's indent and a tab takes the words to where they start in the editor.
        var inserts: [Int: (mark: String, indent: CGFloat)] = [:]
        for bullet in decorations.bullets { inserts[bullet.anchor] = ("•", bullet.indent) }
        for box in decorations.boxes { inserts[box.marker.anchor] = (box.checked ? "☑" : "☐", box.marker.indent) }
        for (anchor, insert) in inserts where anchor < length {
            let line = (storage.string as NSString).lineRange(for: NSRange(location: anchor, length: 0))
            let current = storage.attribute(.paragraphStyle, at: anchor, effectiveRange: nil) as? NSParagraphStyle
            let paragraph = (current?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = insert.indent
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
            storage.addAttribute(.paragraphStyle, value: paragraph, range: line)
        }
        let shown = NSMutableAttributedString()
        var index = 0
        while index <= length {
            if let insert = inserts[index] {
                var attributes =
                    index < length ? storage.attributes(at: index, effectiveRange: nil) : styler.baseAttributes
                attributes[.foregroundColor] = brand.nsColor(.quiet)
                for key in [NSAttributedString.Key.underlineStyle, .backgroundColor, .strikethroughStyle] {
                    attributes[key] = nil
                }
                shown.append(NSAttributedString(string: insert.mark + "\t", attributes: attributes))
            }
            guard index < length else { break }
            var end = index
            while end < length, !decorations.hidden.contains(end), inserts[end] == nil || end == index { end += 1 }
            if end > index {
                shown.append(storage.attributedSubstring(from: NSRange(location: index, length: end - index)))
                index = end
            } else {
                index += 1
            }
        }
        return shown
    }
}

extension ReadingText {
    /// The web or mail address under a point of the read-mode text laid out at `width`, if a link is there.
    static func link(at point: CGPoint, in text: NSAttributedString, width: CGFloat) -> URL? {
        guard text.length > 0 else { return nil }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var fraction: CGFloat = 0
        let index = layout.characterIndex(
            for: point, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        // Past the end of a line the nearest character is reported; only a hit on the words counts.
        let glyph = layout.glyphIndexForCharacter(at: index)
        guard index < storage.length,
            layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point),
            let address = storage.attribute(.thoughtLink, at: index, effectiveRange: nil) as? String,
            let url = URL(string: address), ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    /// Built read-mode texts, so scrolling and redraws reuse them; a few hundred thoughts at most.
    private static var cache: [CacheKey: NSAttributedString] = [:]
    private static var order: [CacheKey] = []
    private static let cacheLimit = 400
    /// The look the cache was built with; another one empties it.
    private static var cachedBrand: BrandTokens?

    private struct CacheKey: Hashable {
        var text: String
        var highlights: [TextHighlight]
        var token: String
    }

    /// `make`, built once per text, marks and look.
    static func cached(text: String, highlights: [TextHighlight], brand: BrandTokens, token: String)
        -> NSAttributedString
    {
        if cachedBrand != brand {
            cache = [:]
            order = []
            cachedBrand = brand
        }
        let key = CacheKey(text: text, highlights: highlights, token: token)
        if let known = cache[key] { return known }
        let built = make(text: text, highlights: highlights, brand: brand, token: token)
        cache[key] = built
        order.append(key)
        if order.count > cacheLimit { cache[order.removeFirst()] = nil }
        return built
    }
}

/// A thought's text in read mode, drawn by AppKit with exactly the editor's attributes (line height, indents,
/// lists), so switching to the editor changes nothing you see. Cheap: no editor, height measured once.
struct ReadingTextView: View {
    let text: String
    let highlights: [TextHighlight]
    var token = "text.thought"
    /// A click on the words, not on a link: flow and stack turn the thought into the editor.
    var onTap: () -> Void = {}
    @Environment(\.brand) private var brand
    @Environment(\.openURL) private var openURL

    var body: some View {
        ReadingTextBody(text: text, highlights: highlights, token: token)
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            // A link opens; anywhere else starts editing.
                            if let brand,
                                let url = ReadingText.link(
                                    at: location,
                                    in: ReadingText.cached(
                                        text: text, highlights: highlights, brand: brand, token: token),
                                    width: proxy.size.width)
                            {
                                openURL(url)
                            } else {
                                onTap()
                            }
                        }
                }
            }
    }
}

private struct ReadingTextBody: NSViewRepresentable {
    let text: String
    let highlights: [TextHighlight]
    let token: String
    @Environment(\.brand) private var brand

    func makeNSView(context: Context) -> ReadingTextNSView { ReadingTextNSView() }

    func updateNSView(_ view: ReadingTextNSView, context: Context) {
        guard let brand else { return }
        let shown = ReadingText.cached(text: text, highlights: highlights, brand: brand, token: token)
        if !view.text.isEqual(to: shown) { view.text = shown }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ReadingTextNSView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.height(for: width))
    }
}

final class ReadingTextNSView: NSView {
    var text = NSAttributedString() {
        didSet {
            heights = MeasuredHeights()
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    private var heights = MeasuredHeights()
    private static let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    override var isFlipped: Bool { true }

    func height(for width: CGFloat) -> CGFloat {
        let text = text
        return heights.height(text: text.string, width: width, style: 0) {
            ceil(
                text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: Self.options)
                    .height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        text.draw(with: bounds, options: Self.options)
    }

    /// Clicks go to SwiftUI, which turns the thought into the editor.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
