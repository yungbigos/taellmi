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

    private func present(selecting entryID: String?) {
        let window = window ?? makeWindow()
        self.window = window
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        if let entryID {
            Task {
                model.showsTrash = false
                await model.refresh()
                await model.select(entryID)
            }
        }
    }

    public func windowWillClose(_ notification: Notification) {
        Task { await model.saveIfNeeded() }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "tällmi"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ExploreView(model: model).brandStyle(brand))
        window.setFrameAutosaveName("ExploreWindow")
        if !window.setFrameUsingName("ExploreWindow") { window.center() }
        window.delegate = self
        return window
    }
}
