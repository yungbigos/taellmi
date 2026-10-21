import AppKit
import Domain
import SwiftUI

/// The editor for a thought's text: its Formatting styled as you type with the markup hidden (ADR 0014), and
/// search highlights drawn on top: search words and, for a related thought, the passage that matched.
/// Highlights are display-only (temporary layout attributes); they never enter the text, so nothing
/// highlighted can be saved. The one place thought text is edited.
///
/// - `grows`: the editor is as tall as its text (flow) instead of scrolling inside its frame (open thought).
/// - `scrollKey`: when it changes (another thought or search), the first highlight is scrolled into view
///   (not in `grows` mode, where the surrounding view does the scrolling).
/// - `formatting`, `shortcuts`: where ⌘K finds this editor, and the formatting keys it handles while you type.
struct HighlightingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var highlights: [TextHighlight]
    var font: String = "text.thought"
    var grows = false
    var scrollKey: String = ""
    var accessibilityLabel = "thought"
    var formatting: FormattingFocus?
    var shortcuts: [Command: Hotkey] = [:]
    /// Takes the keyboard as soon as it appears (the composer).
    var focusOnAppear = false
    /// Esc, when the floating bar isn't showing (the composer closes).
    var onCancel: (() -> Void)?
    /// tällmi's own actions in the text's right-click menu (delete, move to folder, …).
    var menuItems: [EditorMenuItem] = []
    @Environment(\.brand) private var brand
    @Environment(\.colorSchemeContrast) private var contrast

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSView {
        // TextKit 1 on purpose: temporary attributes draw highlights without touching the text, and the layout
        // manager can hide markup glyph by glyph.
        let storage = NSTextStorage()
        let layout = FormattingLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let textView = ThoughtTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.attach(textView)
        guard !grows else {
            textView.isVerticallyResizable = false
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
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.brand = brand
        coordinator.token = font
        coordinator.shortcuts = shortcuts
        coordinator.onCancel = onCancel
        coordinator.menuItems = menuItems
        coordinator.formatting = formatting
        guard let textView = coordinator.textView else { return }
        // While a character is being composed (e.g. option-u for ü), leave the view alone.
        guard !textView.hasMarkedText() else { return }
        if textView.string != text {
            // Replaced from outside (another thought, a saved version): its undo history no longer fits.
            textView.undoManager?.removeAllActions(withTarget: textView.textStorage ?? textView)
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            coordinator.applied = nil
            coordinator.restyle(force: true)
        } else if coordinator.styledWith != StyleKey(brand: brand, token: font) {
            coordinator.restyle(force: true)
        }
        let strong = contrast == .increased
        if coordinator.applied != highlights || coordinator.appliedStrong != strong {
            coordinator.apply(highlights, strong: strong)
            coordinator.applied = highlights
            coordinator.appliedStrong = strong
        }
        if !grows, coordinator.scrolledKey != scrollKey {
            coordinator.scrolledKey = scrollKey
            if let first = highlights.first {
                textView.scrollRangeToVisible(NSRange(location: first.range.lowerBound, length: first.range.count))
            }
        }
        if focusOnAppear, !coordinator.focusedOnAppear {
            coordinator.focusedOnAppear = true
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Height for a given width, measured on a copy so SwiftUI's probing never disturbs the live layout.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard grows, let width = proposal.width, width.isFinite, width > 0,
            let textView = context.coordinator.textView, let storage = textView.textStorage
        else { return nil }
        let coordinator = context.coordinator
        // Measured once per text, width and look: SwiftUI asks constantly while a long flow scrolls, and laying
        // out every thought each time froze the app when scrolling up.
        let height = coordinator.heights.height(
            text: textView.string, width: width, style: coordinator.styleVersion
        ) {
            let measuring = NSTextStorage(attributedString: storage)
            let layout = FormattingLayoutManager()
            layout.decorations = (textView.layoutManager as? FormattingLayoutManager)?.decorations ?? .init()
            let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            measuring.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            let lineHeight = textView.font.map { layout.defaultLineHeight(for: $0) } ?? 0
            return max(layout.usedRect(for: container).height, lineHeight)
        }
        return CGSize(width: width, height: height)
    }

    /// What the text was last styled with; a change restyles it.
    struct StyleKey: Equatable {
        var brand: BrandTokens?
        var token: String
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, FormattingTarget {
        var text: Binding<String>
        weak var textView: ThoughtTextView?
        var brand: BrandTokens?
        var token = "text.thought"
        var shortcuts: [Command: Hotkey] = [:]
        var onCancel: (() -> Void)?
        var menuItems: [EditorMenuItem] = []
        weak var formatting: FormattingFocus?
        var scrolledKey: String?
        var styledWith: StyleKey?
        var applied: [TextHighlight]?
        var appliedStrong = false
        var focusedOnAppear = false
        /// Bumped whenever the look changes, so measured heights are taken again.
        var styleVersion = 0
        var heights = MeasuredHeights()

        private var isFocused = false
        /// The Formatting of the text as it is, read once per change.
        private var read: (text: String, formatting: TextFormatting)?
        private var shown: MarkupVisibility?
        /// Set while the editor itself changes the text, so that change isn't handled as typing.
        private var isApplyingEdit = false
        /// Where the latest typing landed, so only the list there is renumbered.
        private var typedRange: Range<Int>?
        private let bar = FormattingBarController()
        private var barTask: Task<Void, Never>?
        private var scrollObserver: NSObjectProtocol?

        init(text: Binding<String>) {
            self.text = text
        }

        func attach(_ textView: ThoughtTextView) {
            self.textView = textView
            textView.onKeyEquivalent = { [weak self] event in self?.handleKey(event) ?? false }
            textView.onFocusChange = { [weak self] focused in self?.focusChanged(focused) }
            textView.onMouseSelectionEnded = { [weak self] in
                self?.restyle(force: false)
                self?.scheduleBar()
            }
            textView.onCheckboxClick = { [weak self] lineStart in self?.toggleCheckbox(lineStart: lineStart) }
        }

        func detach() {
            barTask?.cancel()
            hideBar()
            if let formatting { formatting.editorDidBlur(self) }
        }

        // MARK: Styling

        /// Styles the text again: always after a change, otherwise only if what is hidden changed.
        func restyle(force: Bool) {
            guard let textView, let storage = textView.textStorage, let brand, !textView.hasMarkedText() else {
                return
            }
            let string = textView.string
            if read?.text != string { read = (string, TextFormatting(string)) }
            guard let formatting = read?.formatting else { return }
            // Only the editor you type in shows markup, around the cursor.
            let visibility = formatting.visibility(selection: isFocused ? Range<Int>(textView.selectedRange()) : nil)
            let key = StyleKey(brand: brand, token: token)
            guard force || visibility != shown || styledWith != key else { return }
            let styler = FormattingStyler(brand: brand, token: token)
            let decorations = styler.apply(to: storage, formatting: formatting, visibility: visibility)
            (textView.layoutManager as? FormattingLayoutManager)?.update(decorations, length: storage.length)
            textView.typingAttributes = styler.baseAttributes
            textView.insertionPointColor = brand.nsColor(.blue)
            shown = visibility
            styledWith = key
            // Only now can the height have changed; ask SwiftUI to measure again (not on every redraw).
            styleVersion += 1
            textView.invalidateIntrinsicContentSize()
            textView.window?.invalidateCursorRects(for: textView)
            if let applied { apply(applied, strong: appliedStrong) }
        }

        func apply(_ highlights: [TextHighlight], strong: Bool) {
            guard let textView, let layout = textView.layoutManager else { return }
            let length = (textView.string as NSString).length
            let all = NSRange(location: 0, length: length)
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: all)
            layout.removeTemporaryAttribute(.underlineColor, forCharacterRange: all)
            // Concept words are underlined, so search highlights can still shade them. A concept's underline
            // is drawn instead of one of yours on the same word (ADR 0014).
            for highlight in highlights {
                guard case .concept = highlight.kind, highlight.range.lowerBound >= 0,
                    highlight.range.upperBound <= length, let color = brand?.nsFill(.concept, increaseContrast: strong)
                else { continue }
                let range = NSRange(highlight.range)
                layout.addTemporaryAttribute(
                    .underlineStyle, value: NSUnderlineStyle.thick.rawValue, forCharacterRange: range)
                layout.addTemporaryAttribute(.underlineColor, value: color, forCharacterRange: range)
            }
            // Passages first, so words drawn on top stay visible inside a shaded passage.
            for highlight in highlights.sorted(by: { $0.kind == .passage && $1.kind == .word }) {
                if case .concept = highlight.kind { continue }
                guard highlight.range.lowerBound >= 0, highlight.range.upperBound <= length else { continue }
                let fill: BrandFillName = highlight.kind == .word ? .matchCurrent : .related
                guard let color = brand?.nsFill(fill, increaseContrast: strong) else { continue }
                layout.addTemporaryAttribute(
                    .backgroundColor, value: color, forCharacterRange: NSRange(highlight.range))
            }
        }

        // MARK: Typing

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            guard !menuItems.isEmpty else { return menu }
            menu.addItem(.separator())
            for item in EditorMenuItem.nsItems(menuItems) { menu.addItem(item) }
            return menu
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !textView.hasMarkedText() else { return }
            if !isApplyingEdit {
                hideBar()
                // Lines added or removed by typing: the numbers of that list follow (one undo step with the
                // typing). Other lists are never touched.
                let selection = Range<Int>(textView.selectedRange()) ?? 0..<0
                if let typed = typedRange,
                    let renumber = FormattingEdits.renumbered(textView.string, around: typed, selection: selection)
                {
                    typedRange = nil
                    apply(renumber)
                    return
                }
            }
            typedRange = nil
            text.wrappedValue = textView.string
            restyle(force: true)
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?
        ) -> Bool {
            if !isApplyingEdit {
                let end = affectedCharRange.location + (replacementString?.utf16.count ?? 0)
                typedRange = affectedCharRange.location..<end
            }
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !textView.isSelectingWithMouse else {
                hideBar()
                return
            }
            restyle(force: false)
            scheduleBar()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let text = textView.string
            let selection = Range<Int>(textView.selectedRange()) ?? 0..<0
            let edit: TextEdit?
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                edit = FormattingEdits.newline(in: text, selection: selection)
            case #selector(NSResponder.deleteBackward(_:)):
                edit = FormattingEdits.deleteBackward(in: text, selection: selection)
            case #selector(NSResponder.insertTab(_:)): edit = FormattingEdits.indent(in: text, selection: selection)
            case #selector(NSResponder.insertBacktab(_:)):
                edit = FormattingEdits.outdent(in: text, selection: selection)
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                if bar.isShown {
                    hideBar()
                    return true
                }
                guard let onCancel else { return false }
                onCancel()
                return true
            default: return false
            }
            guard let edit else { return false }
            apply(edit)
            return true
        }

        /// Applies an edit as one undoable change, then selects what it says.
        private func apply(_ edit: TextEdit) {
            guard let textView, let storage = textView.textStorage else { return }
            let range = NSRange(edit.range)
            guard textView.shouldChangeText(in: range, replacementString: edit.replacement) else { return }
            isApplyingEdit = true
            storage.replaceCharacters(in: range, with: edit.replacement)
            textView.didChangeText()
            isApplyingEdit = false
            textView.setSelectedRange(NSRange(edit.selection))
        }

        // MARK: Formatting

        func applyFormatting(_ action: FormattingAction) {
            guard let textView, textView.isEditable else { return }
            // From ⌘K the keyboard comes back here; the selection was kept.
            if textView.window?.firstResponder !== textView { textView.window?.makeFirstResponder(textView) }
            let text = textView.string
            let selection = Range<Int>(textView.selectedRange()) ?? 0..<0
            let edit: TextEdit? =
                switch action {
                case .toggle(let format): FormattingEdits.toggle(format, in: text, selection: selection)
                case .indent: FormattingEdits.indent(in: text, selection: selection)
                case .outdent: FormattingEdits.outdent(in: text, selection: selection)
                }
            guard let edit else { return }
            let barWasShown = bar.isShown
            apply(edit)
            if barWasShown { showBar() }
        }

        private func toggleCheckbox(lineStart: Int) {
            guard let textView else { return }
            let selection = Range<Int>(textView.selectedRange()) ?? 0..<0
            if let edit = FormattingEdits.toggleCheckbox(in: textView.string, lineAt: lineStart, selection: selection) {
                apply(edit)
            }
        }

        private func handleKey(_ event: NSEvent) -> Bool {
            var modifiers: Hotkey.Modifiers = []
            let flags = event.modifierFlags
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            for command in Commands.all where command.isFormatting {
                guard let hotkey = shortcuts[command], let action = command.formattingAction,
                    hotkey.matches(
                        keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers, modifiers: modifiers
                    )
                else { continue }
                applyFormatting(action)
                return true
            }
            return false
        }

        private func focusChanged(_ focused: Bool) {
            isFocused = focused
            if focused {
                formatting?.editorDidFocus(self)
            } else {
                formatting?.editorDidBlur(self)
                hideBar()
            }
            restyle(force: false)
        }

        // MARK: The floating bar

        /// Shows the bar once the selection has stayed still for a moment.
        private func scheduleBar() {
            barTask?.cancel()
            guard let textView, isFocused, textView.isEditable, textView.selectedRange().length > 0 else {
                hideBar()
                return
            }
            let delay = brand?.motion.formatBar?.delay ?? 0
            barTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.showBar()
            }
        }

        private func showBar() {
            guard let textView, let window = textView.window, isFocused else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else {
                hideBar()
                return
            }
            let upper = textView.firstRect(forCharacterRange: range, actualRange: nil)
            let lower = textView.firstRect(
                forCharacterRange: NSRange(location: NSMaxRange(range) - 1, length: 1), actualRange: nil)
            let active = FormattingEdits.activeFormats(in: textView.string, selection: Range<Int>(range) ?? 0..<0)
            var labels: [Format: String] = [:]
            for command in Commands.all {
                if let format = command.format, let hotkey = shortcuts[command] { labels[format] = hotkey.displayLabel }
            }
            let content = FormattingBarView(active: active, shortcuts: labels) { [weak self] format in
                self?.applyFormatting(.toggle(format))
            }
            bar.show(above: upper, below: lower, in: window, brand: brand, content: content)
            observeScrolling(of: textView)
        }

        private func hideBar() {
            barTask?.cancel()
            bar.hide()
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            scrollObserver = nil
        }

        /// Scrolling moves the words away from the bar, so it goes.
        private func observeScrolling(of textView: NSTextView) {
            guard scrollObserver == nil, let clip = textView.enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideBar() }
            }
        }
    }
}
