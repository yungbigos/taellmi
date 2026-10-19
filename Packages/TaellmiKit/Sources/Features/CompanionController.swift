import AppKit
import Domain
import SwiftUI

/// tälli's settings, read from config by the composition root.
public struct CompanionSettings: Sendable {
    public var cursorOffset: Double
    public var savedDisplaySeconds: Double
    public var followsCursor: Bool
    /// Share of the remaining way tälli covers per frame when following (0…1).
    public var followSmoothing: Double
    /// Keys claimed only while tälli is open.
    public var finishKey: Hotkey
    public var cancelKey: Hotkey

    public init(
        cursorOffset: Double, savedDisplaySeconds: Double, followsCursor: Bool, followSmoothing: Double,
        finishKey: Hotkey, cancelKey: Hotkey
    ) {
        self.finishKey = finishKey
        self.cancelKey = cancelKey
        self.cursorOffset = cursorOffset
        self.savedDisplaySeconds = savedDisplaySeconds
        self.followsCursor = followsCursor
        self.followSmoothing = followSmoothing
    }
}

/// A floating panel that never takes focus from the app you are in (until you click into it to type).
final class CompanionPanel: NSPanel {
    static let size = CGSize(width: 340, height: 150)

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.nonactivatingPanel, .borderless],
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

/// Shows tälli next to the cursor for Capture and hides it again.
public final class CompanionController {
    private let model: CaptureViewModel
    private let appearance: AppearanceViewModel
    private let settings: CompanionSettings
    private let hotkeys: GlobalHotkeyMonitor
    private let panel = CompanionPanel()
    private var showsSaved = false
    private var hideTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    /// The app you were in when tälli appeared; it gets the keyboard back when tälli hides.
    private var previousApp: NSRunningApplication?
    /// Bumped whenever the input field should take focus (after the panel became key).
    private var focusRequest = 0
    private let onOpenEntry: (String) -> Void
    private static let cancelHotkeyID: UInt32 = 2
    private static let finishHotkeyID: UInt32 = 3

    public init(
        model: CaptureViewModel, appearance: AppearanceViewModel, settings: CompanionSettings,
        hotkeys: GlobalHotkeyMonitor, onOpenEntry: @escaping (String) -> Void
    ) {
        self.onOpenEntry = onOpenEntry
        self.model = model
        self.appearance = appearance
        self.settings = settings
        self.hotkeys = hotkeys
        render()
    }

    /// The capture hotkey: show and start listening, or finish and save.
    public func toggle() async {
        if model.isRecording {
            await model.toggle()
            if model.errorMessage == nil { await confirmSavedAndHide() } else { render() }
        } else if panel.isVisible, !model.typedText.trimmingCharacters(in: .whitespaces).isEmpty {
            await submitTyped()
        } else {
            showAtCursor()
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

    private func showAtCursor() {
        hideTask?.cancel()
        showsSaved = false
        render()
        panel.setFrame(targetFrame(), display: true)
        startFollowing()
        panel.alphaValue = 0
        // Typing only reaches tälli when tällmi is the active app, so activate briefly and remember where
        // you were; hiding hands the keyboard straight back to that app.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = frontmost }
        NSApplication.shared.activate()
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
        showsSaved = true
        render()
        hideTask = Task { [weak self, settings] in
            try? await Task.sleep(for: .seconds(settings.savedDisplaySeconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Where tälli wants to be right now: beside the cursor, on the screen the cursor is on.
    private func targetFrame() -> CGRect {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        return CompanionPlacement.frame(
            cursor: cursor, size: CompanionPanel.size, screen: screen?.visibleFrame ?? .zero,
            offset: settings.cursorOffset)
    }

    /// Glides after the cursor about 60 times a second while visible. Reading the cursor position
    /// needs no extra permission.
    private func startFollowing() {
        followTask?.cancel()
        guard settings.followsCursor else { return }
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                let current = panel.frame.origin
                let next = CompanionFollow.step(
                    from: current, to: targetFrame().origin, smoothing: settings.followSmoothing)
                if next != current { panel.setFrameOrigin(next) }
            }
        }
    }

    private func hide() {
        followTask?.cancel()
        followTask = nil
        previousApp?.activate()
        previousApp = nil
        hotkeys.unregister(id: Self.cancelHotkeyID)
        hotkeys.unregister(id: Self.finishHotkeyID)
        showsSaved = false
        NSAnimationContext.runAnimationGroup { [panel] context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func render() {
        panel.contentView = NSHostingView(
            rootView: CompanionView(
                model: model, showsSaved: showsSaved, focusRequest: focusRequest,
                hint: "\(settings.finishKey.displayLabel) fertig · \(settings.cancelKey.displayLabel) verwerfen",
                onSubmitTyped: { [weak self] in Task { await self?.submitTyped() } },
                onOpenSaved: { [weak self] in self?.openSavedEntry() }
            )
            .textCase(appearance.swiftUICase))
    }
}
