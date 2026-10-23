import AppKit

// tällmi shows in the Dock and in ⌘Tab only while one of its windows is open; otherwise it lives in the menu bar.
enum DockPresence {
    static func windowOpened() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    // Leaves the Dock only when no other tällmi window is still open (panels like the menu bar's don't count).
    static func windowWillClose(_ closing: NSWindow?) {
        let othersOpen = NSApplication.shared.windows.contains {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel)
        }
        if !othersOpen { NSApplication.shared.setActivationPolicy(.accessory) }
    }
}
