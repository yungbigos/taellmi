import AppKit

/// The system file picker for the imports, "import from apple notes …" and "import from whatsapp …". Works in
/// the sandbox: what you pick is readable.
enum ImportFilePicker {
    static let notesExplanation =
        "export your notes from apple notes as markdown, then pick the files or their folder here. each note becomes a thought, dated by its file. notes already here are skipped."

    static let chatExplanation =
        "in whatsapp, export your chat with yourself and send it to this mac. unzip it, then pick its _chat.txt or its folder here. each message becomes a thought, dated when you sent it. messages already here are skipped."

    @MainActor static func choose(explaining explanation: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = explanation
        panel.prompt = "import"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
