import AppKit
import SwiftUI

/// tälli's settings, read from config by the composition root.
public struct CompanionSettings: Sendable {
    public var cursorOffset: Double
    public var savedDisplaySeconds: Double

    public init(cursorOffset: Double, savedDisplaySeconds: Double) {
        self.cursorOffset = cursorOffset
        self.savedDisplaySeconds = savedDisplaySeconds
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
    private let settings: CompanionSettings
    private let hotkeys: GlobalHotkeyMonitor
    private let panel = CompanionPanel()
    private var showsSaved = false
    private var hideTask: Task<Void, Never>?
    private static let escapeHotkeyID: UInt32 = 2

    public init(model: CaptureViewModel, settings: CompanionSettings, hotkeys: GlobalHotkeyMonitor) {
        self.model = model
        self.settings = settings
        self.hotkeys = hotkeys
        render()
    }

    /// The capture hotkey: show and start listening, or finish and save.
    public func toggle() async {
        if model.isRecording {
            await model.toggle()
            if model.errorMessage == nil { await confirmSavedAndHide() } else { render() }
        } else if panel.isVisible, !model.typedText.isEmpty {
            await submitTyped()
        } else {
            showAtCursor()
            await model.toggle()
            if !model.isRecording { render() }
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

    private func showAtCursor() {
        hideTask?.cancel()
        showsSaved = false
        render()
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let frame = CompanionPlacement.frame(
            cursor: cursor, size: CompanionPanel.size, screen: screen?.visibleFrame ?? .zero,
            offset: settings.cursorOffset)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.18
            panel.animator().alphaValue = 1
        }
        hotkeys.register(.escape, id: Self.escapeHotkeyID) { [weak self] in
            Task { await self?.cancel() }
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

    private func hide() {
        hotkeys.unregister(id: Self.escapeHotkeyID)
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
            rootView: CompanionView(model: model, showsSaved: showsSaved) { [weak self] in
                Task { await self?.submitTyped() }
            })
    }
}
