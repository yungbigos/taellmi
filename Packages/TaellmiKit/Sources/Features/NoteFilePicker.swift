import AppKit

/// The system file picker for "import from apple notes …". Works in the sandbox: what you pick is readable.
enum NoteFilePicker {
    static let explanation =
        "export your notes from apple notes as markdown, then pick the files or their folder here. each note becomes a thought, dated by its file. notes already here are skipped."

    @MainActor static func choose() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = explanation
        panel.prompt = "import"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
