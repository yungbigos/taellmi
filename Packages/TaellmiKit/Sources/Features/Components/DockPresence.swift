import AppKit

// tällmi shows in the Dock and in ⌘Tab only while one of its windows is open; otherwise it lives in the menu bar.
enum DockPresence {
    // Brings tällmi to the front with `window` focused. A menu bar app that just joined the Dock is only let to
    // the front once that change has landed, so it asks again on the next turn of the run loop.
    static func show(_ window: NSWindow) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        // In front of other apps' windows even when macOS keeps the focus elsewhere (e.g. tällmi was started in
        // the background): it is seen, and one click takes the focus.
        window.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    // Leaves the Dock only when no other tällmi window is still open (panels like the menu bar's don't count).
    static func windowWillClose(_ closing: NSWindow?) {
        let othersOpen = NSApplication.shared.windows.contains {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel)
        }
        if !othersOpen { NSApplication.shared.setActivationPolicy(.accessory) }
    }
}
