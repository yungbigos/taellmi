import Config
import Domain
import os

extension AppEnvironment {
    /// The brand tokens from config (`brand.tokens`). `nil` only if the config is broken, in which case the
    /// windows fall back to plain macOS styling instead of failing.
    public var brand: BrandTokens? {
        do {
            return try BrandTokens(json: settings.value(SettingKeys.brandTokens))
        } catch {
            Logger(subsystem: "app.taellmi", category: "AppComposition")
                .error("brand tokens unreadable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
