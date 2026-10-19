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
                    onOpenArchive: { controller.openExplore() })
            } else {
                Text(controller.startupError ?? "Starte …").padding()
            }
        } label: {
            Image(systemName: controller.isRecording ? "record.circle.fill" : "waveform")
                .accessibilityLabel("tällmi")
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let environment = controller.environment, let hotkey = controller.hotkeySettings,
                let exploreHotkey = controller.exploreHotkeySettings
            {
                SettingsView(
                    hotkey: hotkey, exploreHotkey: exploreHotkey, appearance: environment.appearanceModel,
                    vocabulary: environment.vocabularyModel)
            } else {
                Text(controller.startupError ?? "Starte …").padding()
            }
        }
    }
}
