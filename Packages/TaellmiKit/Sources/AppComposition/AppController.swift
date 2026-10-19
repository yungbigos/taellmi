import Domain
import Features
import Foundation
import Observation
import SystemServices
import os

/// Owns the running app: builds the environment, starts it, and wires the global hotkey.
@Observable
public final class AppController {
    public private(set) var environment: AppEnvironment?
    public private(set) var startupError: String?

    @ObservationIgnored private let hotkeys = GlobalHotkeyMonitor()
    @ObservationIgnored private var companion: CompanionController?
    /// Set when the configured hotkey clashes with a macOS shortcut.
    public private(set) var hotkeyWarning: String?
    public private(set) var hotkeySettings: HotkeySettingsViewModel?
    @ObservationIgnored private let checker = SystemHotkeyChecker()
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
        logger.notice("macOS reports \(SystemHotkeyChecker.systemShortcuts().count) system shortcuts")
        hotkeySettings = HotkeySettingsViewModel(store: environment.hotkeyStore, checker: checker) {
            [weak self] hotkey in self?.registerCaptureHotkey(hotkey)
        }
        let companion = CompanionController(
            model: environment.captureModel, appearance: environment.appearanceModel,
            settings: environment.companionSettings(), hotkeys: hotkeys)
        self.companion = companion
        if let hotkey = environment.hotkey { registerCaptureHotkey(hotkey) }
    }

    /// (Re-)registers the hotkey that calls tälli, and notes a clash with macOS shortcuts.
    private func registerCaptureHotkey(_ hotkey: Hotkey) {
        hotkeyLabel = hotkey.displayLabel
        hotkeyWarning = checker.conflict(for: hotkey).map(HotkeySettingsViewModel.conflictText)
        guard let companion else { return }
        hotkeys.register(hotkey, id: 1) { Task { await companion.toggle() } }
    }

    /// "⌥⌘ Leertaste"-style label for the menu.
    public nonisolated static func label(for hotkey: Hotkey) -> String {
        hotkey.displayLabel
    }
}
