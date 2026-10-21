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
        // Bullets and boxes go before the item's words; everything the editor hides is left out.
        var inserts: [Int: String] = [:]
        for bullet in decorations.bullets { inserts[bullet.anchor] = "• " }
        for box in decorations.boxes { inserts[box.marker.anchor] = box.checked ? "☑ " : "☐ " }
        let shown = NSMutableAttributedString()
        let quiet: [NSAttributedString.Key: Any] = styler.baseAttributes.merging(
            [.foregroundColor: brand.nsColor(.quiet)]) { _, new in new }
        var index = 0
        while index <= length {
            if let marker = inserts[index] { shown.append(NSAttributedString(string: marker, attributes: quiet)) }
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
    /// Built read-mode texts, so scrolling and redraws reuse them; a few hundred thoughts at most.
    private static var cache: [CacheKey: AttributedString] = [:]
    private static var order: [CacheKey] = []
    private static let cacheLimit = 400

    private struct CacheKey: Hashable {
        var text: String
        var highlights: [TextHighlight]
        var token: String
    }
    /// The look the cache was built with; another one empties it.
    private static var cachedBrand: BrandTokens?

    /// The SwiftUI text for read mode, built once per text, marks and look.
    static func attributed(text: String, highlights: [TextHighlight], brand: BrandTokens, token: String)
        -> AttributedString
    {
        if cachedBrand != brand {
            cache = [:]
            order = []
            cachedBrand = brand
        }
        let key = CacheKey(text: text, highlights: highlights, token: token)
        if let known = cache[key] { return known }
        let built = swiftUI(make(text: text, highlights: highlights, brand: brand, token: token))
        cache[key] = built
        order.append(key)
        if order.count > cacheLimit { cache[order.removeFirst()] = nil }
        return built
    }

    /// Carries the editor's fonts, colours, marks and lines over to SwiftUI's text attributes.
    private static func swiftUI(_ source: NSAttributedString) -> AttributedString {
        var result = AttributedString()
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
            var run = AttributedString(source.attributedSubstring(from: range).string)
            if let font = attributes[.font] as? NSFont { run.font = Font(font as CTFont) }
            if let color = attributes[.foregroundColor] as? NSColor { run.foregroundColor = Color(nsColor: color) }
            if let color = attributes[.backgroundColor] as? NSColor { run.backgroundColor = Color(nsColor: color) }
            if attributes[.underlineStyle] != nil {
                let color = (attributes[.underlineColor] as? NSColor).map { Color(nsColor: $0) }
                run.underlineStyle = Text.LineStyle(pattern: .solid, color: color)
            }
            if attributes[.strikethroughStyle] != nil { run.strikethroughStyle = .single }
            result.append(run)
        }
        return result
    }
}

/// A thought's text in read mode.
struct ReadingTextView: View {
    let text: String
    let highlights: [TextHighlight]
    var token = "text.thought"
    @Environment(\.brand) private var brand

    var body: some View {
        if let brand {
            Text(ReadingText.attributed(text: text, highlights: highlights, brand: brand, token: token))
                .lineSpacing(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
