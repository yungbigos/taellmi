import SwiftUI

/// Read-only text with search words marked, for list rows and the ⌘K palette.
struct HighlightedText: View {
    let text: String
    /// UTF-16 ranges in `text` to mark.
    let ranges: [Range<Int>]
    var fill: BrandFillName = .matchCurrent
    @Environment(\.brand) private var brand
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var attributed = AttributedString(text)
        guard let brand, let fill = brand.fill(fill, increaseContrast: contrast == .increased) else {
            return attributed
        }
        let units = text.utf16.count
        for range in ranges where range.lowerBound >= 0 && range.upperBound <= units {
            let start = String.Index(utf16Offset: range.lowerBound, in: text)
            let end = String.Index(utf16Offset: range.upperBound, in: text)
            guard let marked = Range(start..<end, in: attributed) else { continue }
            attributed[marked].backgroundColor = brand.color(fill.color).opacity(fill.opacity)
        }
        return attributed
    }
}

/// The small "related" label on a thought found only by meaning.
struct RelatedLabel: View {
    var body: some View {
        Text("related")
            .brandFont("text.label")
            .brandForeground(.quiet)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .brandFill(.related)
            .accessibilityLabel("found by meaning, not by your words")
    }
}
