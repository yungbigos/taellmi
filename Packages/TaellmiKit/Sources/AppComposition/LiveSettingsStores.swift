import Config
import Features
import Foundation

/// The `capture.hotkey` setting.
nonisolated struct LiveHotkeyStore: HotkeyStore {
    let settings: SettingsStore
    let editor: ConfigEditor

    func current() async throws -> String { try settings.string(SettingKeys.hotkey) }
    func save(_ value: String) async throws { try editor.setSetting(SettingKeys.hotkey, to: .string(value)) }
}

/// The `appearance.text_case` setting.
nonisolated struct LiveAppearanceStore: AppearanceStore {
    let settings: SettingsStore
    let editor: ConfigEditor

    func textCase() async throws -> String { try settings.string(SettingKeys.textCase) }
    func setTextCase(_ value: String) async throws { try editor.setSetting(SettingKeys.textCase, to: .string(value)) }
}
