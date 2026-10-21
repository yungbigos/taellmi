import AppKit

/// An action tällmi adds to the right-click menu of a thought's text, after the system's own text actions.
struct EditorMenuItem {
    var title: String
    var isDestructive = false
    var children: [EditorMenuItem] = []
    var action: (() -> Void)?

    /// AppKit menu items that call back into SwiftUI.
    static func nsItems(_ items: [EditorMenuItem]) -> [NSMenuItem] {
        items.map { item in
            let menuItem = NSMenuItem(
                title: item.title, action: item.action == nil ? nil : #selector(MenuActionTarget.fire(_:)),
                keyEquivalent: "")
            if let action = item.action {
                menuItem.target = MenuActionTarget.shared
                menuItem.representedObject = MenuActionTarget.Action(run: action)
            }
            if !item.children.isEmpty {
                let submenu = NSMenu(title: item.title)
                for child in nsItems(item.children) { submenu.addItem(child) }
                menuItem.submenu = submenu
            }
            return menuItem
        }
    }
}

/// One long-lived target for those items (menu items hold their target weakly); each item carries its action.
final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    final class Action: NSObject {
        let run: () -> Void
        init(run: @escaping () -> Void) { self.run = run }
    }

    @objc func fire(_ sender: NSMenuItem) {
        (sender.representedObject as? Action)?.run()
    }
}
