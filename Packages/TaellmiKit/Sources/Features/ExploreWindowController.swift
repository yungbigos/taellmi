import AppKit
import Domain
import SwiftUI

/// Opens the Explore window. While it is open, tällmi shows in the Dock and in ⌘Tab like a normal app.
public final class ExploreWindowController: NSObject, NSWindowDelegate {
    private let model: ExploreViewModel
    private var window: NSWindow?
    /// The brand tokens from config, applied to the window content.
    public var brand: BrandTokens?
    /// Asks for Touch ID or your password first when "lock tällmi with touch id" is on.
    private let authorize: () async -> Bool

    public init(model: ExploreViewModel, authorize: @escaping () async -> Bool = { true }) {
        self.model = model
        self.authorize = authorize
    }

    public func show(selecting entryID: String? = nil) {
        if window?.isVisible == true {
            present(selecting: entryID)
            return
        }
        Task {
            guard await authorize() else { return }
            present(selecting: entryID)
        }
    }

    /// Loads first, then shows, so the window never appears empty.
    private func present(selecting entryID: String?) {
        Task {
            await model.open(selecting: entryID)
            let window = window ?? makeWindow()
            self.window = window
            DockPresence.windowOpened()
            window.makeKeyAndOrderFront(nil)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        Task { await model.saveIfNeeded() }
        DockPresence.windowWillClose(notification.object as? NSWindow)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "tällmi"
        // tälli takes the title's place (ExploreView); the name stays for the Window menu and ⌘Tab.
        window.titleVisibility = .hidden
        // The toolbar floats over the content instead of sitting on its own grey band.
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        let cursor: @MainActor () -> CGPoint? = { [weak window] in
            guard let window, window.isVisible, let content = window.contentView else { return nil }
            let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            return CGPoint(x: point.x, y: content.bounds.height - point.y)
        }
        window.contentView = NSHostingView(rootView: ExploreView(model: model, cursor: cursor).brandStyle(brand))
        window.setFrameAutosaveName("ExploreWindow")
        if !window.setFrameUsingName("ExploreWindow") { window.center() }
        window.delegate = self
        return window
    }
}
