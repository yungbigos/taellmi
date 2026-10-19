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
    public private(set) var exploreHotkeySettings: HotkeySettingsViewModel?
    /// One shortcut editor per command, in catalogue order.
    public private(set) var commandShortcutSettings: [(Command, HotkeySettingsViewModel)] = []
    @ObservationIgnored private var explore: ExploreWindowController?
    @ObservationIgnored private var captureWarning: String?
    @ObservationIgnored private var exploreWarning: String?
    private static let captureHotkeyID: UInt32 = 1
    private static let exploreHotkeyID: UInt32 = 4
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
            startupError = "tällmi couldn't start. details are in the system log."
            return
        }
        logger.notice("macOS reports \(SystemHotkeyChecker.systemShortcuts().count) system shortcuts")
        hotkeySettings = HotkeySettingsViewModel(store: environment.hotkeyStore, checker: checker) {
            [weak self] hotkey in self?.registerCaptureHotkey(hotkey)
        }
        exploreHotkeySettings = HotkeySettingsViewModel(store: environment.exploreHotkeyStore, checker: checker) {
            [weak self] hotkey in self?.registerExploreHotkey(hotkey)
        }
        let explore = ExploreWindowController(model: environment.exploreModel)
        self.explore = explore
        let companion = CompanionController(
            model: environment.captureModel, appearance: environment.appearanceModel,
            settings: environment.companionSettings(), hotkeys: hotkeys
        ) { entryID in explore.show(selecting: entryID) }
        self.companion = companion
        environment.exploreModel.onNewThought = { Task { await companion.toggle() } }
        let settings = environment.settings
        commandShortcutSettings = Commands.all.map { command in
            let checker = CombinedConflictChecker([
                checker,
                CommandShortcutChecker(current: { CommandShortcuts.load(from: settings) }, ignoring: command),
            ])
            let model = HotkeySettingsViewModel(store: environment.commandShortcutStore(command), checker: checker) {
                _ in environment.exploreModel.shortcuts = environment.commandShortcuts()
            }
            return (command, model)
        }
        if let hotkey = environment.hotkey { registerCaptureHotkey(hotkey) }
        if let hotkey = environment.exploreHotkey { registerExploreHotkey(hotkey) }
    }

    /// Opens the Explore window ("Archiv öffnen").
    public func openExplore() {
        explore?.show()
    }

    private func registerExploreHotkey(_ hotkey: Hotkey) {
        exploreWarning = checker.conflict(for: hotkey).map {
            "open tällmi: " + HotkeySettingsViewModel.conflictText($0)
        }
        updateWarning()
        guard let explore else { return }
        hotkeys.register(hotkey, id: Self.exploreHotkeyID) { explore.show() }
    }

    private func updateWarning() {
        let warnings = [captureWarning, exploreWarning].compactMap { $0 }
        hotkeyWarning = warnings.isEmpty ? nil : warnings.joined(separator: " ")
    }

    /// (Re-)registers the hotkey that calls tälli, and notes a clash with macOS shortcuts.
    private func registerCaptureHotkey(_ hotkey: Hotkey) {
        hotkeyLabel = hotkey.displayLabel
        captureWarning = checker.conflict(for: hotkey).map(HotkeySettingsViewModel.conflictText)
        updateWarning()
        guard let companion else { return }
        hotkeys.register(hotkey, id: Self.captureHotkeyID) { Task { await companion.toggle() } }
    }

    /// "⌥⌘ space"-style label for the menu.
    public nonisolated static func label(for hotkey: Hotkey) -> String {
        hotkey.displayLabel
    }
}
