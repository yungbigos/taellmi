import AppKit
import Domain
import SwiftUI

/// The floating bar over a selection in a thought (ADR 0014, docs/brand.md §7): bold · italic · underline ·
/// strike through · bullet list · numbered list. A format that is on shows in blue.
struct FormattingBarView: View {
    var active: Set<Format>
    var shortcuts: [Format: String]
    var action: (Format) -> Void

    var body: some View {
        BarIsland {
            ForEach(Format.allCases, id: \.self) { format in
                BarChip(
                    title: Self.title(format), symbol: Self.symbol(format), selected: active.contains(format),
                    showsTitle: false
                ) { action(format) }
                .help(shortcuts[format].map { "\(Self.title(format)) \($0)" } ?? Self.title(format))
            }
        }
        .fixedSize()
    }

    static func title(_ format: Format) -> String {
        switch format {
        case .bold: Command.formatBold.title
        case .italic: Command.formatItalic.title
        case .underline: Command.formatUnderline.title
        case .strikethrough: Command.formatStrikethrough.title
        case .bulletList: Command.formatBulletList.title
        case .numberedList: Command.formatNumberedList.title
        }
    }

    static func symbol(_ format: Format) -> String {
        switch format {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        }
    }
}

/// A borderless panel that never takes the keyboard, so the thought keeps its cursor and selection.
private final class FormattingBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a format button work although the bar's panel is never the key window.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows the formatting bar above a selection (below it if there is no room) as a child of the thought's
/// window, so it moves with it.
@MainActor
final class FormattingBarController {
    private var panel: FormattingBarPanel?
    private var hosting: FirstClickHostingView<AnyView>?

    var isShown: Bool { panel?.isVisible ?? false }

    func show(
        above selection: NSRect, below lowerEdge: NSRect, in window: NSWindow, brand: BrandTokens?,
        content: FormattingBarView
    ) {
        let root = AnyView(content.brandStyle(brand))
        let panel = panel ?? makePanel()
        if let hosting {
            hosting.rootView = root
        } else {
            let hosting = FirstClickHostingView(rootView: root)
            self.hosting = hosting
            panel.contentView = hosting
        }
        let size = hosting?.fittingSize ?? .zero
        let gap = CGFloat(brand?.space(.xs) ?? 0)
        let screen = window.screen?.visibleFrame ?? .infinite
        var origin = NSPoint(x: selection.midX - size.width / 2, y: selection.maxY + gap)
        if origin.y + size.height > screen.maxY { origin.y = lowerEdge.minY - gap - size.height }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFront(nil)
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : (brand?.motion.formatBar?.duration ?? 0)
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> FormattingBarPanel {
        let panel = FormattingBarPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        self.panel = panel
        return panel
    }
}
