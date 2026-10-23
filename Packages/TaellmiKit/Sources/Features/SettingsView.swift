import AppKit
import Domain
import SwiftUI

/// The Settings window: General (tälli's shortcut, writing style) and Vocabulary.
public struct SettingsView: View {
    var hotkey: HotkeySettingsViewModel
    var exploreHotkey: HotkeySettingsViewModel
    var appearance: AppearanceViewModel
    var vocabulary: VocabularyViewModel
    var commandShortcuts: [(Command, HotkeySettingsViewModel)]
    var privacy: PrivacyViewModel
    var openAtLogin: OpenAtLoginModel
    var showRecoveryKey: () -> Void

    public init(
        hotkey: HotkeySettingsViewModel, exploreHotkey: HotkeySettingsViewModel, appearance: AppearanceViewModel,
        vocabulary: VocabularyViewModel, commandShortcuts: [(Command, HotkeySettingsViewModel)],
        privacy: PrivacyViewModel, openAtLogin: OpenAtLoginModel, showRecoveryKey: @escaping () -> Void
    ) {
        self.privacy = privacy
        self.openAtLogin = openAtLogin
        self.showRecoveryKey = showRecoveryKey
        self.commandShortcuts = commandShortcuts
        self.hotkey = hotkey
        self.exploreHotkey = exploreHotkey
        self.appearance = appearance
        self.vocabulary = vocabulary
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(
                hotkey: hotkey, exploreHotkey: exploreHotkey, appearance: appearance, openAtLogin: openAtLogin
            )
            .tabItem { Label("general", systemImage: "gearshape") }
            VocabularySettingsView(model: vocabulary)
                .tabItem { Label("spellings", systemImage: "character.book.closed") }
            ShortcutSettingsView(rows: commandShortcuts)
                .tabItem { Label("shortcuts", systemImage: "keyboard") }
            PrivacySettingsView(model: privacy, showRecoveryKey: showRecoveryKey)
                .tabItem { Label("privacy", systemImage: "lock") }
        }
        .containerBackground(for: .window) { BrandSurfaceBackground(kind: .panel, radius: nil) }
        .textCase(appearance.swiftUICase)
    }
}

struct GeneralSettingsView: View {
    @Bindable var hotkey: HotkeySettingsViewModel
    @Bindable var exploreHotkey: HotkeySettingsViewModel
    var appearance: AppearanceViewModel
    var openAtLogin: OpenAtLoginModel

    var body: some View {
        Form {
            Section {
                LabeledContent("hotkey") {
                    HotkeyRecorder(model: hotkey)
                }
                if let warning = hotkey.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .brandStatus(.warning)
                }
            } header: {
                Text("call tälli")
            } footer: {
                Text("tälli appears next to your cursor and listens.")
            }
            Section("open tällmi") {
                LabeledContent("hotkey") {
                    HotkeyRecorder(model: exploreHotkey)
                }
                if let warning = exploreHotkey.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .brandStatus(.warning)
                }
            }
            Section {
                Toggle(
                    "open tällmi at login",
                    isOn: Binding(get: { openAtLogin.isOn }, set: { openAtLogin.set($0) }))
            }
            Section("appearance") {
                Picker(
                    "show your thoughts",
                    selection: Binding(
                        get: { appearance.isLowercase },
                        set: { on in Task { await appearance.setLowercase(on) } })
                ) {
                    Text("as written").tag(false)
                    Text("all lowercase").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 460, height: 400)
        .task {
            await hotkey.load()
            await exploreHotkey.load()
            openAtLogin.load()
        }
        .shortcutConflictAlert(hotkey)
    }
}

/// Every command with its shortcut. Click a shortcut, then press the new keys.
struct ShortcutSettingsView: View {
    var rows: [(Command, HotkeySettingsViewModel)]

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.0) { command, model in
                    ShortcutRow(title: command.title, model: model)
                }
            } footer: {
                Text("these work while the tällmi window is in front.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 460, height: 420)
    }
}

private struct ShortcutRow: View {
    let title: String
    @Bindable var model: HotkeySettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HotkeyRecorder(model: model)
            }
            if let warning = model.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .brandFont("text.label")
                    .brandStatus(.warning)
            }
        }
        .task { await model.load() }
        .shortcutConflictAlert(model)
    }
}
