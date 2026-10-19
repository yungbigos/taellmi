import Features
import Foundation
import Observation
import os

/// Owns the running app: builds the environment, starts it, and wires the global hotkey.
@Observable
public final class AppController {
    public private(set) var environment: AppEnvironment?
    public private(set) var startupError: String?

    @ObservationIgnored private let hotkeys = GlobalHotkeyMonitor()
    @ObservationIgnored private var companion: CompanionController?
    @ObservationIgnored private let logger = Logger(subsystem: "app.taellmi", category: "app")

    public init() {
        Task { await self.start() }
    }

    public var isRecording: Bool { environment?.captureModel.isRecording ?? false }

    public private(set) var hotkeyLabel = ""

    private func start() async {
        let environment: AppEnvironment
        do {
            environment = try await AppEnvironment.live()
            self.environment = environment
            try await environment.start()
        } catch {
            logger.error("Start failed: \(String(describing: error))")
            startupError = "tällmi konnte nicht starten. Details stehen im Systemprotokoll."
            return
        }
        if let hotkey = environment.hotkey {
            hotkeyLabel = Self.label(for: hotkey)
            let companion = CompanionController(
                model: environment.captureModel, settings: environment.companionSettings(), hotkeys: hotkeys)
            self.companion = companion
            hotkeys.register(hotkey) { Task { await companion.toggle() } }
        }
    }

    /// "⌥⌘ Leertaste"-style label for the menu.
    public nonisolated static func label(for hotkey: Hotkey) -> String {
        var symbols = ""
        if hotkey.modifiers.contains(.control) { symbols += "⌃" }
        if hotkey.modifiers.contains(.option) { symbols += "⌥" }
        if hotkey.modifiers.contains(.shift) { symbols += "⇧" }
        if hotkey.modifiers.contains(.command) { symbols += "⌘" }
        switch hotkey.key {
        case .space: return symbols + " Leertaste"
        case .escape: return symbols + "Esc"
        case .letter(let character): return symbols + String(character).uppercased()
        }
    }
}
