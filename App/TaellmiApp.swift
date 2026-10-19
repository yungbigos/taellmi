import AppComposition
import Features
import SwiftUI

@main
struct TaellmiApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            if let environment = controller.environment {
                MenuBarView(model: environment.captureModel, hotkeyLabel: controller.hotkeyLabel)
            } else {
                Text(controller.startupError ?? "Starte …").padding()
            }
        } label: {
            Image(systemName: controller.isRecording ? "record.circle.fill" : "waveform")
                .accessibilityLabel("tällmi")
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let environment = controller.environment {
                VocabularySettingsView(model: environment.vocabularyModel)
            } else {
                Text(controller.startupError ?? "Starte …").padding()
            }
        }
    }
}
