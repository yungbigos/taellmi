import AppKit
import Domain
import SwiftUI

/// An editable thought text with search highlights drawn on top: search words and, for a related thought,
/// the passage that matched. Highlights are display-only (temporary layout attributes); they never enter the
/// text, so nothing highlighted can be saved. The one place thought text is edited with highlights.
///
/// - `grows`: the editor is as tall as its text (flow) instead of scrolling inside its frame (open thought).
/// - `scrollKey`: when it changes (another thought or search), the first highlight is scrolled into view
///   (not in `grows` mode, where the surrounding view does the scrolling).
struct HighlightingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var highlights: [TextHighlight]
    var font: String = "text.thought"
    var grows = false
    var scrollKey: String = ""
    var accessibilityLabel = "thought"
    @Environment(\.brand) private var brand
    @Environment(\.colorSchemeContrast) private var contrast

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSView {
        // TextKit 1 on purpose: temporary attributes draw highlights without touching the text.
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.textView = textView
        guard !grows else {
            textView.isVerticallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            return textView
        }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        guard let textView = coordinator.textView else { return }
        // While a character is being composed (e.g. option-u for ü), leave the view alone.
        guard !textView.hasMarkedText() else { return }
        if let brand, coordinator.styledWith != font {
            coordinator.styledWith = font
            style(textView, brand: brand)
        }
        if textView.string != text {
            // Replaced from outside (another thought, a saved version): its undo history no longer fits.
            textView.undoManager?.removeAllActions(withTarget: textView.textStorage ?? textView)
            let selection = textView.selectedRange()
            textView.string = text
            if let brand { style(textView, brand: brand) }
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            coordinator.applied = nil
        }
        let strong = contrast == .increased
        if coordinator.applied != highlights || coordinator.appliedStrong != strong {
            apply(highlights, to: textView, strong: strong)
            coordinator.applied = highlights
            coordinator.appliedStrong = strong
        }
        if grows { textView.invalidateIntrinsicContentSize() }
        if !grows, coordinator.scrolledKey != scrollKey {
            coordinator.scrolledKey = scrollKey
            if let first = highlights.first {
                textView.scrollRangeToVisible(NSRange(location: first.range.lowerBound, length: first.range.count))
            }
        }
    }

    /// Height for a given width, measured on a copy so SwiftUI's probing never disturbs the live layout.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard grows, let width = proposal.width, width.isFinite, width > 0,
            let textView = context.coordinator.textView, let storage = textView.textStorage
        else { return nil }
        let measuring = NSTextStorage(attributedString: storage)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        measuring.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let lineHeight = textView.font.map { layout.defaultLineHeight(for: $0) } ?? 0
        return CGSize(width: width, height: max(layout.usedRect(for: container).height, lineHeight))
    }

    private func style(_ textView: NSTextView, brand: BrandTokens) {
        let font = brand.nsFont(self.font)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = brand.lineHeightMultiple(self.font)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: brand.nsColor(.ink), .paragraphStyle: paragraph,
        ]
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = paragraph
        textView.insertionPointColor = brand.nsColor(.blue)
        if let storage = textView.textStorage {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    private func apply(_ highlights: [TextHighlight], to textView: NSTextView, strong: Bool) {
        guard let layout = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        // Passages first, so words drawn on top stay visible inside a shaded passage.
        for highlight in highlights.sorted(by: { $0.kind == .passage && $1.kind == .word }) {
            guard highlight.range.lowerBound >= 0, highlight.range.upperBound <= length else { continue }
            let fill: BrandFillName = highlight.kind == .word ? .matchCurrent : .related
            guard let color = brand?.nsFill(fill, increaseContrast: strong) else { continue }
            layout.addTemporaryAttribute(
                .backgroundColor, value: color,
                forCharacterRange: NSRange(location: highlight.range.lowerBound, length: highlight.range.count))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?
        var scrolledKey: String?
        var styledWith: String?
        var applied: [TextHighlight]?
        var appliedStrong = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !textView.hasMarkedText() else { return }
            text.wrappedValue = textView.string
        }
    }
}
