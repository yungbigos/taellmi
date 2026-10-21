import AppKit
import Domain

extension NSAttributedString.Key {
    /// The address of a link in a thought, opened with ⌘-click.
    static let thoughtLink = NSAttributedString.Key("app.taellmi.thought-link")
}

/// Turns a thought's Formatting into what the editor shows (ADR 0014): fonts, lines and colours as text
/// attributes, and what the layout hides and draws. Looks come from the brand tokens (docs/brand.md §6).
struct FormattingStyler {
    let brand: BrandTokens
    /// The type style of the thought's text, e.g. `text.thought`.
    let token: String

    /// The attributes new text starts with.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: brand.nsFont(token), .foregroundColor: brand.nsColor(.ink), .paragraphStyle: paragraph(token)]
    }

    /// Styles the whole text and returns what the layout manager should hide and draw.
    func apply(to storage: NSTextStorage, formatting: TextFormatting, visibility: MarkupVisibility)
        -> FormattingDecorations
    {
        let length = storage.length
        let string = storage.string as NSString
        let hidden = IndexSet(ranges: visibility.hidden)
        var decorations = FormattingDecorations()
        decorations.hidden = hidden
        decorations.bulletColor = brand.nsColor(.quiet)
        decorations.boxColor = brand.nsColor(.quiet)
        decorations.tickColor = brand.nsColor(.blue)
        decorations.tickMarkColor = brand.nsColor(.paper)
        decorations.quoteBarWidth = CGFloat(brand.space(.xxs))
        let step = CGFloat(brand.space(.l))

        // Which type style each character uses, and whether it is bold or italic.
        var lineToken = [String](repeating: token, count: length)
        var bold = [Bool](repeating: false, count: length)
        var italic = [Bool](repeating: false, count: length)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: length))

        for line in formatting.lines where line.range.upperBound <= length {
            let range = NSRange(line.range)
            switch line.kind {
            case .heading(let level):
                let heading = "\(token).heading\(min(max(level, 1), 3))"
                for index in line.range { lineToken[index] = heading }
                storage.addAttribute(.paragraphStyle, value: paragraph(heading), range: range)
            case .listItem(let style, let level):
                let indent = CGFloat(level) * step
                let shownMarker = line.indentation.upperBound..<line.content.lowerBound
                let markerHidden = hidden.contains(integersIn: shownMarker) && !shownMarker.isEmpty
                let markerWidth = string.substring(with: NSRange(shownMarker)).size(withAttributes: baseAttributes)
                    .width
                let paragraph = paragraph(token)
                switch style {
                case .numbered:
                    paragraph.firstLineHeadIndent = indent
                    paragraph.headIndent = indent + markerWidth
                case .bullet, .checklist:
                    paragraph.headIndent = indent + step
                    paragraph.firstLineHeadIndent =
                        markerHidden ? indent + step : max(indent, indent + step - markerWidth)
                }
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
                let marker = FormattingDecorations.Marker(anchor: line.content.lowerBound, indent: indent)
                if visibility.bullets.contains(line.range.lowerBound) { decorations.bullets.append(marker) }
                if visibility.boxes.contains(line.range.lowerBound), case .checklist(let checked) = style {
                    decorations.boxes.append((marker, checked))
                }
            case .quote:
                let paragraph = paragraph(token)
                paragraph.firstLineHeadIndent = step
                paragraph.headIndent = step
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
                decorations.quotes.append(NSRange(line.content.lowerBound..<line.range.upperBound))
            case .plain, .code:
                break
            }
        }

        for span in formatting.spans where span.full.upperBound <= length {
            let content = NSRange(span.content)
            switch span.style {
            case .bold: for index in span.content { bold[index] = true }
            case .italic: for index in span.content { italic[index] = true }
            case .strikethrough:
                storage.addAttributes(
                    [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: brand.nsColor(.ink)],
                    range: content)
            case .underline:
                storage.addAttributes(
                    [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: brand.nsColor(.ink)],
                    range: content)
            case .link(let url):
                storage.addAttributes([.foregroundColor: brand.nsColor(.blue), .thoughtLink: url], range: content)
            case .image:
                break
            }
        }

        // Fonts, in runs of the same style.
        var start = 0
        while start < length {
            var end = start + 1
            while end < length, lineToken[end] == lineToken[start], bold[end] == bold[start],
                italic[end] == italic[start]
            {
                end += 1
            }
            if lineToken[start] != token || bold[start] || italic[start] {
                storage.addAttribute(
                    .font, value: brand.nsFont(lineToken[start], bold: bold[start], italic: italic[start]),
                    range: NSRange(location: start, length: end - start))
            }
            start = end
        }

        // Markup that stays visible is quiet, so the words stand out.
        let quiet = brand.nsColor(.quiet)
        for line in formatting.lines
        where !line.marker.isEmpty && line.kind != .code && line.marker.upperBound <= length {
            storage.addAttribute(.foregroundColor, value: quiet, range: NSRange(line.marker))
        }
        for span in formatting.spans where span.full.upperBound <= length {
            storage.addAttribute(.foregroundColor, value: quiet, range: NSRange(span.opening))
            storage.addAttribute(.foregroundColor, value: quiet, range: NSRange(span.closing))
        }
        storage.endEditing()

        let whisper = brand.nsFont("text.whisper")
        for position in visibility.placeholders {
            decorations.placeholders[position] = .init(
                text: String(localized: "image not imported"), font: whisper, color: quiet)
        }
        return decorations
    }

    /// The brand's line height as space between lines rather than taller lines: same look, but the cursor
    /// stays the height of the text instead of the whole line.
    private func paragraph(_ token: String) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        let natural = Self.naturalLineHeight(brand.nsFont(token))
        paragraph.lineSpacing = max(0, natural * (brand.lineHeightMultiple(token) - 1))
        return paragraph
    }

    @MainActor private static var naturalHeights: [String: CGFloat] = [:]

    @MainActor static func naturalLineHeight(_ font: NSFont) -> CGFloat {
        let key = "\(font.fontName)-\(font.pointSize)"
        if let known = naturalHeights[key] { return known }
        let height = NSLayoutManager().defaultLineHeight(for: font)
        naturalHeights[key] = height
        return height
    }
}

extension IndexSet {
    init(ranges: [Range<Int>]) {
        self.init()
        for range in ranges { insert(integersIn: range) }
    }
}
