import Config
import Features
import Foundation

/// A hotkey setting (`capture.hotkey`, `explore.hotkey`).
nonisolated struct LiveHotkeyStore: HotkeyStore {
    let settings: SettingsStore
    let editor: ConfigEditor
    let key: String

    func current() async throws -> String { try settings.string(key) }
    func save(_ value: String) async throws { try editor.setSetting(key, to: .string(value)) }
}

/// The `appearance.text_case` setting.
nonisolated struct LiveAppearanceStore: AppearanceStore {
    let settings: SettingsStore
    let editor: ConfigEditor

    func textCase() async throws -> String { try settings.string(SettingKeys.textCase) }
    func setTextCase(_ value: String) async throws { try editor.setSetting(SettingKeys.textCase, to: .string(value)) }
}
