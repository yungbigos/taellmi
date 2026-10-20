import AppKit
import Domain
import Features
import Foundation
import Observation
import Persistence
import SystemServices
import os

/// Owns the running app: builds the environment, starts it, and wires the global hotkey.
@Observable
public final class AppController {
    public private(set) var environment: AppEnvironment?
    public private(set) var startupError: String?
    /// The brand tokens, read once from config at startup.
    public private(set) var brand: BrandTokens?
    /// The menu bar dots, quiet and listening, drawn once from the brand tokens.
    public private(set) var menuBarIcons: (quiet: NSImage, listening: NSImage)?

    @ObservationIgnored private let hotkeys = GlobalHotkeyMonitor()
    @ObservationIgnored private var companion: CompanionController?
    /// Set when the configured hotkey clashes with a macOS shortcut.
    public private(set) var hotkeyWarning: String?
    public private(set) var hotkeySettings: HotkeySettingsViewModel?
    public private(set) var exploreHotkeySettings: HotkeySettingsViewModel?
    /// One shortcut editor per command, in catalogue order.
    public private(set) var commandShortcutSettings: [(Command, HotkeySettingsViewModel)] = []
    public private(set) var privacy: PrivacyViewModel?
    @ObservationIgnored private var panel: NSWindow?
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
            await Self.waitForOtherInstances()
            environment = try await AppEnvironment.live()
            self.environment = environment
            defer { if environment.pendingRecoveryKey != nil { showRecoveryKey() } }
            try await environment.start()
        } catch let locked as ArchiveLockedError {
            askForRecoveryKey(locked.vault)
            return
        } catch is ArchiveVault.Error {
            startupError =
                "the key file of your thoughts is missing or still downloading. wait for it, then open tällmi again."
            return
        } catch is ArchiveUnavailableError {
            startupError =
                "the folder where your thoughts are stored isn't available. connect it and open tällmi again."
            return
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
        let settingsStore = environment.settings
        let explore = ExploreWindowController(model: environment.exploreModel) {
            await WindowLock.authorize(settings: settingsStore)
        }
        privacy = environment.makePrivacyModel { Self.relaunch() }
        if let failed = environment.migrationFailures, failed > 0 {
            startupError =
                "\(failed) thoughts couldn't be encrypted and are not shown. they are safe in a backup; see privacy settings."
        }
        self.explore = explore
        let companion = CompanionController(
            model: environment.captureModel, appearance: environment.appearanceModel,
            settings: environment.companionSettings(), hotkeys: hotkeys
        ) { entryID in explore.show(selecting: entryID) }
        self.companion = companion
        brand = environment.brand
        menuBarIcons = (
            MenuBarDots.image(listening: false, tokens: brand), MenuBarDots.image(listening: true, tokens: brand)
        )
        explore.brand = brand
        companion.brand = brand
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

    /// Shows the new Recovery Key until you confirm you saved it.
    public func showRecoveryKey() {
        guard let environment, let key = environment.pendingRecoveryKey else { return }
        let model = RecoveryKeyViewModel(recoveryKey: key.formatted) { group, keep in
            try environment.confirmRecoveryKey(lastGroup: group, keepInKeychain: keep)
        }
        panel?.close()
        panel = PanelWindow.show(title: "recovery key", brand: environment.brand) {
            RecoveryKeyView(model: model) { [weak self] in
                self?.panel?.close()
                Task { await self?.privacy?.load() }
            }
        }
    }

    /// On a new Mac: unlock the Archive with its Recovery Key, then start.
    private func askForRecoveryKey(_ vault: ArchiveVault) {
        let model = UnlockArchiveViewModel { text in
            let recovery = try RecoveryKey(parsing: text)
            _ = try vault.unlock(with: recovery)
            return true
        }
        panel = PanelWindow.show(title: "unlock tällmi", brand: AppEnvironment.seededBrand) {
            UnlockArchiveView(model: model) { [weak self] in
                self?.panel?.close()
                Task { await self?.start() }
            }
        }
    }

    /// Starts a fresh copy of tällmi and quits this one (after moving the Archive).
    private static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }

    /// The new instance waits (up to 15 s) until the old one has quit, so nothing is written into the old
    /// Archive folder while it is being moved.
    nonisolated static func waitForOtherInstances() async {
        let me = ProcessInfo.processInfo.processIdentifier
        for _ in 0..<60 {
            let others = NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.taellmi"
            )
            .filter { $0.processIdentifier != me }
            if others.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Opens the Explore window ("Archiv öffnen").
    public func openExplore(selecting entryID: String? = nil) {
        explore?.show(selecting: entryID)
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
