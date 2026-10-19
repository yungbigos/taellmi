import Config
import Domain

/// Reads every command's shortcut from config. A missing or unreadable setting means "no shortcut".
nonisolated enum CommandShortcuts {
    static func load(from settings: SettingsStore) -> [Command: Hotkey] {
        var shortcuts: [Command: Hotkey] = [:]
        for command in Commands.all {
            if let text = try? settings.string(command.settingKey), let hotkey = try? Hotkey(parsing: text) {
                shortcuts[command] = hotkey
            }
        }
        return shortcuts
    }
}
