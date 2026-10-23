import AppKit

// The system folder picker: where your thoughts are stored, in privacy settings and in the onboarding.
enum FolderPicker {
    @MainActor static func choose(prompt: String, message: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        if let message { panel.message = message }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
