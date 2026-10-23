import AppKit
import Domain
import SwiftUI

/// The first-launch window. While it is open tällmi shows in the Dock. When it closes, finished or not, the app is
/// told, so it can open the tällmi window (and show a recovery key that still waits).
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: OnboardingModel
    private let talli: OnboardingTalliSizes
    private let brand: BrandTokens?
    private let onClose: (_ finished: Bool) -> Void
    private var window: NSWindow?

    public init(
        model: OnboardingModel, talli: OnboardingTalliSizes, brand: BrandTokens?,
        onClose: @escaping (_ finished: Bool) -> Void
    ) {
        self.model = model
        self.talli = talli
        self.brand = brand
        self.onClose = onClose
    }

    public func show() {
        let window = window ?? makeWindow()
        self.window = window
        DockPresence.show(window)
    }

    public var isVisible: Bool { window?.isVisible == true }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        // The tällmi window opens next and keeps tällmi in the Dock.
        onClose(model.isFinished)
    }

    private func makeWindow() -> NSWindow {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: OnboardingView.size), styleMask: style, backing: .buffered,
            defer: false)
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
        let content = NSHostingView(
            rootView: OnboardingView(model: model, talli: talli, cursor: cursor) { [weak self] in self?.close() }
                // The content runs under the transparent title bar: the whole window is the onboarding.
                .ignoresSafeArea()
                .background { BrandSurfaceBackground(kind: .panel, radius: nil).ignoresSafeArea() }
                .brandStyle(brand))
        // Otherwise the hosting view grows the window by the title bar to fit the content below it.
        content.sizingOptions = []
        window.contentView = content
        window.setFrame(CGRect(origin: .zero, size: OnboardingView.size), display: false)
        window.center()
        window.delegate = self
        return window
    }
}
