import ServiceManagement
import os

/// "open tällmi at login", through macOS's own login items (System Settings › General › Login Items).
public enum LoginItem {
    private static let logger = Logger(subsystem: "app.taellmi", category: "login-item")

    public static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns it on or off and returns what macOS really did.
    @discardableResult
    public static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            logger.error("Could not change the login item: \(String(describing: error))")
        }
        return isOn
    }
}
