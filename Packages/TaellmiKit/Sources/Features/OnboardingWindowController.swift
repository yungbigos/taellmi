import AppKit
import Domain
import SwiftUI

/// The first-launch window. While it is open tällmi shows in the Dock; when it closes before the end, the app is
/// told, so a recovery key that still waits is not lost.
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: OnboardingModel
    private let talli: OnboardingTalliSizes
    private let brand: BrandTokens?
    private let onClosedEarly: () -> Void
    private var window: NSWindow?

    public init(
        model: OnboardingModel, talli: OnboardingTalliSizes, brand: BrandTokens?,
        onClosedEarly: @escaping () -> Void
    ) {
        self.model = model
        self.talli = talli
        self.brand = brand
        self.onClosedEarly = onClosedEarly
    }

    public func show() {
        let window = window ?? makeWindow()
        self.window = window
        DockPresence.windowOpened()
        window.makeKeyAndOrderFront(nil)
    }

    public var isVisible: Bool { window?.isVisible == true }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        DockPresence.windowWillClose(notification.object as? NSWindow)
        if !model.isFinished { onClosedEarly() }
    }

    private func makeWindow() -> NSWindow {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // The content runs under the transparent title bar, so the whole window is the onboarding's size.
        let window = NSWindow(
            contentRect: NSWindow.contentRect(
                forFrameRect: CGRect(origin: .zero, size: OnboardingView.size), styleMask: style),
            styleMask: style, backing: .buffered, defer: false)
        window.title = "tällmi"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let cursor: @MainActor () -> CGPoint? = { [weak window] in
            guard let window, window.isVisible, let content = window.contentView else { return nil }
            let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            return CGPoint(x: point.x, y: content.bounds.height - point.y)
        }
        window.contentView = NSHostingView(
            rootView: OnboardingView(model: model, talli: talli, cursor: cursor) { [weak self] in self?.close() }
                .background { BrandSurfaceBackground(kind: .panel, radius: nil).ignoresSafeArea() }
                .brandStyle(brand))
        window.center()
        window.delegate = self
        return window
    }
}
