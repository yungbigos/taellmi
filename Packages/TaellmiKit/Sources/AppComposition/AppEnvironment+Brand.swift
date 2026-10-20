import Config
import Domain
import os

extension AppEnvironment {
    /// The brand tokens from config (`brand.tokens`). `nil` only if the config is broken, in which case the
    /// windows fall back to plain macOS styling instead of failing.
    public var brand: BrandTokens? {
        Self.brand(stored: try? settings.value(SettingKeys.brandTokens))
    }

    /// The stored brand row, or the shipped tokens when it can't be read. A row the user edited is never
    /// replaced by a seed upgrade, so it can be an older version that lacks newer tokens; falling back keeps the
    /// windows branded instead of dropping to plain macOS styling.
    static func brand(stored: JSONValue?) -> BrandTokens? {
        let logger = Logger(subsystem: "app.taellmi", category: "AppComposition")
        guard let stored else {
            logger.error("brand tokens missing, using the shipped ones")
            return seededBrand
        }
        do {
            return try BrandTokens(json: stored)
        } catch {
            logger.error(
                "brand tokens unreadable, using the shipped ones: \(String(describing: error), privacy: .public)")
            return seededBrand
        }
    }

    /// The brand tokens as shipped, for the unlock panel that shows before the archive and its config are open.
    static var seededBrand: BrandTokens? {
        guard let setting = try? SeedBundle.bundled().settings.first(where: { $0.key == SettingKeys.brandTokens })
        else { return nil }
        return try? BrandTokens(json: setting.value)
    }
}
