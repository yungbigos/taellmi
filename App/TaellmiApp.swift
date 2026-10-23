import AppComposition
import Features
import SwiftUI

@main
struct TaellmiApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            if let environment = controller.environment {
                MenuBarView(
                    model: environment.captureModel, appearance: environment.appearanceModel,
                    hotkeyLabel: controller.hotkeyLabel, hotkeyWarning: controller.hotkeyWarning,
                    onOpenArchive: { controller.openExplore() },
                    onOpenThought: { controller.openExplore(selecting: $0) }
                )
                .brandStyle(controller.brand)
            } else {
                Text(controller.startupError ?? "starting …").padding()
            }
        } label: {
            if let icons = controller.menuBarIcons {
                Image(nsImage: controller.isRecording ? icons.listening : icons.quiet)
                    .accessibilityLabel("tällmi")
            } else {
                Text("tällmi")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let environment = controller.environment, let hotkey = controller.hotkeySettings,
                let exploreHotkey = controller.exploreHotkeySettings, let privacy = controller.privacy
            {
                SettingsView(
                    hotkey: hotkey, exploreHotkey: exploreHotkey, appearance: environment.appearanceModel,
                    vocabulary: environment.vocabularyModel, commandShortcuts: controller.commandShortcutSettings,
                    privacy: privacy, openAtLogin: controller.openAtLogin,
                    showRecoveryKey: { controller.showRecoveryKey() }
                )
                .brandStyle(controller.brand)
            } else {
                Text(controller.startupError ?? "starting …").padding()
            }
        }
    }
}
