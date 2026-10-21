import AppKit

/// The native text view behind the thought editor. It reports focus and finished selections, lets the editor
/// handle formatting keys while you type, ticks checkboxes and opens links on ⌘-click (ADR 0014).
final class ThoughtTextView: NSTextView {
    /// Formatting shortcuts; true when the key press was one.
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onFocusChange: ((Bool) -> Void)?
    /// After a mouse selection ends (the button is up again).
    var onMouseSelectionEnded: (() -> Void)?
    /// A checkbox was clicked; the argument is a position on its line.
    var onCheckboxClick: ((Int) -> Void)?
    /// Shown, quiet, while the text is empty (the composer's "or type …").
    var placeholder: NSAttributedString? {
        didSet { needsDisplay = true }
    }

    /// The height of a line of text without the space between lines. macOS sizes its cursor to the whole line,
    /// that space included, which looks huge; the cursor is trimmed to this.
    var cursorHeight: CGFloat?
    private var isTrimmingCursor = false

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let indicator = subview as? NSTextInsertionIndicator else { return }
        indicator.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(cursorMoved(_:)), name: NSView.frameDidChangeNotification, object: indicator)
        trimCursor(indicator)
    }

    @objc private func cursorMoved(_ notification: Notification) {
        if let indicator = notification.object as? NSTextInsertionIndicator { trimCursor(indicator) }
    }

    /// The space between lines sits below each line, so the cursor keeps its top and loses only that space.
    private func trimCursor(_ indicator: NSTextInsertionIndicator) {
        guard !isTrimmingCursor, let height = cursorHeight, indicator.frame.height > height + 0.5 else { return }
        isTrimmingCursor = true
        indicator.frame.size.height = height
        isTrimmingCursor = false
    }

    /// While the mouse is selecting, hidden markup stays as it is, so the text doesn't jump under the pointer.
    private(set) var isSelectingWithMouse = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Every editor in the window is asked; only the one you type in acts.
        if window?.firstResponder === self, onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let lineStart = checkbox(at: point) {
            onCheckboxClick?(lineStart)
            return
        }
        if event.modifierFlags.contains(.command), let url = link(at: point) {
            NSWorkspace.shared.open(url)
            return
        }
        isSelectingWithMouse = true
        // NSTextView tracks the drag itself and returns once the button is released.
        super.mouseDown(with: event)
        isSelectingWithMouse = false
        onMouseSelectionEnded?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let layout = layoutManager as? FormattingLayoutManager else { return }
        for anchor in layout.boxAnchors {
            if let rect = layout.boxRect(forAnchor: anchor) { addCursorRect(inView(rect), cursor: .pointingHand) }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder else { return }
        placeholder.draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y))
    }

    // MARK: Hit testing

    private func checkbox(at point: NSPoint) -> Int? {
        guard isEditable, let layout = layoutManager as? FormattingLayoutManager else { return nil }
        return layout.boxAnchors.first { anchor in
            layout.boxRect(forAnchor: anchor).map { inView($0).contains(point) } ?? false
        }
    }

    /// Only web and mail addresses open; anything else in an imported note stays text.
    private func link(at point: NSPoint) -> URL? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
            storage.length > 0
        else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layout.characterIndex(
            for: inContainer, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length,
            let address = storage.attribute(.thoughtLink, at: index, effectiveRange: nil) as? String,
            let url = URL(string: address), ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    private func inView(_ rect: NSRect) -> NSRect {
        rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }
}
