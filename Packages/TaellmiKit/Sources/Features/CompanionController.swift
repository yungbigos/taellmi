import AppKit
import Domain
import SwiftUI

/// tälli's settings, read from config by the composition root.
public struct CompanionSettings: Sendable {
    /// How far from the cursor tälli appears when you call it.
    public var cursorOffset: Double
    public var savedDisplaySeconds: Double
    /// How big tälli is in its panel, in points.
    public var talliSize: Double
    /// Keys claimed only while tälli is open.
    public var finishKey: Hotkey
    public var cancelKey: Hotkey
    /// Where you last dropped tälli, as config text ("x,y"); empty means beside the cursor.
    public var position: String
    /// How much of what you're saying the bubble shows: its last this many characters.
    public var previewCharacters: Int

    public init(
        cursorOffset: Double, savedDisplaySeconds: Double, talliSize: Double, finishKey: Hotkey, cancelKey: Hotkey,
        position: String = "", previewCharacters: Int = 140
    ) {
        self.position = position
        self.previewCharacters = previewCharacters
        self.talliSize = talliSize
        self.finishKey = finishKey
        self.cancelKey = cancelKey
        self.cursorOffset = cursorOffset
        self.savedDisplaySeconds = savedDisplaySeconds
    }
}

/// A floating panel that never takes focus from the app you are in (until you click into it to type).
final class CompanionPanel: NSPanel {
    /// Room for tälli at `talliSize` beside a bubble of a fixed width.
    static func size(talliSize: CGFloat) -> CGSize {
        CGSize(width: 276 + talliSize, height: max(150, talliSize + 20))
    }

    init(size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

/// Shows tälli next to the cursor for Capture and hides it again. In between tälli stays where it appeared,
/// watching the cursor, until you drag it somewhere else.
public final class CompanionController {
    private let model: CaptureViewModel
    private let appearance: AppearanceViewModel
    private let settings: CompanionSettings
    private let hotkeys: GlobalHotkeyMonitor
    private let panel: CompanionPanel
    private let panelSize: CGSize
    /// The brand tokens from config, applied to tälli's panel.
    public var brand: BrandTokens?
    private var showsSaved = false
    private var showsDiscarded = false
    private var hideTask: Task<Void, Never>?
    private var isShown = false
    /// Where the pointer and the panel were when you pressed on tälli, and whether it has become a drag.
    private var press: (mouse: CGPoint, frame: CGRect, isDrag: Bool)?
    /// Where you last dropped tälli; it comes back there next time.
    private var droppedAt: CGPoint?
    private let savePosition: (String) -> Void
    private var pokes = 0
    private var stirs = 0
    /// Bumped whenever the input field should take focus (after the panel became key).
    private var focusRequest = 0
    /// Counts appearances, so tälli comes alive once per appearance and keeps its state while it is shown.
    private var showCount = 0
    private var hosting: NSHostingView<AnyView>?
    private let onOpenEntry: (String) -> Void
    private static let cancelHotkeyID: UInt32 = 2
    private static let finishHotkeyID: UInt32 = 3

    public init(
        model: CaptureViewModel, appearance: AppearanceViewModel, settings: CompanionSettings,
        hotkeys: GlobalHotkeyMonitor, savePosition: @escaping (String) -> Void = { _ in },
        onOpenEntry: @escaping (String) -> Void
    ) {
        self.savePosition = savePosition
        droppedAt = CompanionPlacement.decode(settings.position)
        self.onOpenEntry = onOpenEntry
        self.model = model
        self.appearance = appearance
        self.settings = settings
        self.hotkeys = hotkeys
        panelSize = CompanionPanel.size(talliSize: settings.talliSize)
        panel = CompanionPanel(size: panelSize)
        render()
    }

    /// The capture hotkey: show and start listening, or finish and save.
    public func toggle() async {
        if model.isRecording {
            let discardedBefore = model.lastDiscardedAt
            await model.toggle()
            if model.lastDiscardedAt != discardedBefore {
                await confirmAndHide(discarded: true)
            } else if model.errorMessage == nil {
                await confirmSavedAndHide()
            } else {
                render()
            }
        } else if panel.isVisible, !model.typedText.trimmingCharacters(in: .whitespaces).isEmpty {
            await submitTyped()
        } else {
            showNearCursor()
            await model.toggle()
            if !model.isRecording { render() }
        }
    }

    /// Enter: save the recording or the typed text and disappear.
    public func finish() async {
        if model.isRecording || !model.typedText.trimmingCharacters(in: .whitespaces).isEmpty {
            await toggle()
        } else {
            hide()
        }
    }

    /// Esc: throw the recording away and disappear.
    public func cancel() async {
        await model.cancel()
        model.typedText = ""
        hide()
    }

    private func submitTyped() async {
        await model.submitTyped()
        if model.errorMessage == nil { await confirmSavedAndHide() } else { render() }
    }

    private func openSavedEntry() {
        guard let id = model.lastSavedEntryID else { return }
        hideTask?.cancel()
        hide()
        onOpenEntry(id)
    }

    private func showNearCursor() {
        hideTask?.cancel()
        showsSaved = false
        showsDiscarded = false
        isShown = true
        showCount += 1
        render()
        // Where you last dropped tälli, if that spot is still on a screen; otherwise beside the cursor.
        let screens = NSScreen.screens.map(\.visibleFrame)
        panel.setFrame(
            CompanionPlacement.remembered(droppedAt, size: panelSize, screens: screens) ?? frameNearCursor(),
            display: true)
        panel.alphaValue = 0
        // The non-activating panel takes the keyboard without making tällmi the active app (like Spotlight),
        // so tällmi's window stays where it is and the app you were in keeps its place. The field takes focus
        // once the panel is key (focusRequest).
        panel.makeKeyAndOrderFront(nil)
        focusRequest += 1
        render()
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.18
            panel.animator().alphaValue = 1
        }
        hotkeys.register(settings.cancelKey, id: Self.cancelHotkeyID) { [weak self] in
            Task { await self?.cancel() }
        }
        hotkeys.register(settings.finishKey, id: Self.finishHotkeyID) { [weak self] in
            Task { await self?.finish() }
        }
    }

    private func confirmSavedAndHide() async {
        await confirmAndHide(discarded: false)
    }

    /// Shows "saved." or "discarded." briefly, then fades out.
    private func confirmAndHide(discarded: Bool) async {
        showsSaved = !discarded
        showsDiscarded = discarded
        render()
        hideTask = Task { [weak self, settings] in
            try? await Task.sleep(for: .seconds(settings.savedDisplaySeconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Beside the cursor, on the screen the cursor is on.
    private func frameNearCursor() -> CGRect {
        let cursor = NSEvent.mouseLocation
        return CompanionPlacement.frame(
            cursor: cursor, size: panelSize, screen: screen(containing: cursor),
            offset: settings.cursorOffset)
    }

    private func screen(containing point: CGPoint) -> CGRect {
        (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? .zero
    }

    /// The pointer in the panel's SwiftUI coordinates (origin top-left). Reading it needs no extra permission.
    private func cursorInPanel() -> CGPoint? {
        guard isShown, let content = panel.contentView else { return nil }
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        return CGPoint(x: point.x, y: content.bounds.height - point.y)
    }

    /// Measured in screen points from where you pressed, so the panel moving under the pointer doesn't feed
    /// back into the drag. Only once the pointer moved past the tolerance does the press become a drag.
    private func drag() {
        let mouse = NSEvent.mouseLocation
        guard var start = press else {
            press = (mouse, panel.frame, false)
            return
        }
        if !start.isDrag {
            let tolerance = brand?.motion.attention?.dragTolerancePt ?? 0
            guard CompanionPlacement.isDrag(from: start.mouse, to: mouse, tolerance: tolerance) else { return }
            start.isDrag = true
            press = start
            stirs += 1
            render()
        }
        let moved = CompanionPlacement.dragged(
            start.frame, by: CGVector(dx: mouse.x - start.mouse.x, dy: mouse.y - start.mouse.y),
            screen: screen(containing: mouse))
        panel.setFrameOrigin(moved.origin)
    }

    /// Letting go: a press that never became a drag was a poke.
    private func endPress() {
        if press?.isDrag == true {
            stirs += 1
            droppedAt = panel.frame.origin
            savePosition(CompanionPlacement.encode(panel.frame.origin))
        } else {
            pokes += 1
        }
        press = nil
        render()
    }

    private func hide() {
        isShown = false
        press = nil
        hotkeys.unregister(id: Self.cancelHotkeyID)
        hotkeys.unregister(id: Self.finishHotkeyID)
        showsSaved = false
        showsDiscarded = false
        NSAnimationContext.runAnimationGroup { [panel] context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, panel] in
            MainActor.assumeIsolated {
                // Called again while fading out: stay.
                guard let self, !self.isShown else { return }
                panel.orderOut(nil)
                self.render()
            }
        }
    }

    private func render() {
        let content = AnyView(
            CompanionView(
                model: model, showsSaved: showsSaved, showsDiscarded: showsDiscarded, focusRequest: focusRequest,
                hint: "\(settings.finishKey.displayLabel) save · \(settings.cancelKey.displayLabel) discard",
                isShown: isShown,
                cursor: { [weak self] in self?.cursorInPanel() },
                talliSize: settings.talliSize, previewCharacters: settings.previewCharacters, panelSize: panelSize,
                pokes: pokes, stirs: stirs,
                onSubmitTyped: { [weak self] in Task { await self?.submitTyped() } },
                onOpenSaved: { [weak self] in self?.openSavedEntry() },
                onDrag: { [weak self] in self?.drag() },
                onDragEnded: { [weak self] in self?.endPress() }
            )
            .id(showCount)
            .textCase(appearance.swiftUICase)
            .brandStyle(brand))
        // Updating the same hosting view keeps tälli's motion state (a new one would replay the entrance).
        if let hosting {
            hosting.rootView = content
        } else {
            let hosting = NSHostingView(rootView: content)
            self.hosting = hosting
            panel.contentView = hosting
        }
    }
}
