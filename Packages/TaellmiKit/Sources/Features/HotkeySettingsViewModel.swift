import Domain
import Foundation
import Observation

/// Reads and writes the `capture.hotkey` setting. Implemented in the composition root.
public protocol HotkeyStore: Sendable {
    func current() async throws -> String
    func save(_ value: String) async throws
}

/// Settings: choose the key combination that calls tälli, with a warning when macOS already uses it.
@Observable
public final class HotkeySettingsViewModel {
    public private(set) var label = ""
    public private(set) var warning: String?
    /// A taken combination waiting for "use it anyway".
    public private(set) var pendingConflict: (hotkey: Hotkey, owner: String)?
    public var isRecording = false {
        didSet { if isRecording != oldValue { onRecordingChange?(isRecording) } }
    }
    /// Told when recording starts and stops, so the app can pause its own shortcuts meanwhile: a registered
    /// shortcut would otherwise take the keys before the recorder sees them.
    @ObservationIgnored public var onRecordingChange: ((Bool) -> Void)?

    @ObservationIgnored private let store: any HotkeyStore
    @ObservationIgnored private let checker: any HotkeyConflictChecking
    @ObservationIgnored private let apply: (Hotkey) -> Void

    public init(
        store: any HotkeyStore, checker: any HotkeyConflictChecking, apply: @escaping (Hotkey) -> Void = { _ in }
    ) {
        self.store = store
        self.checker = checker
        self.apply = apply
    }

    public func load() async {
        guard let text = try? await store.current(), let hotkey = try? Hotkey(parsing: text) else {
            warning = "the saved shortcut is invalid. set a new one."
            return
        }
        label = hotkey.displayLabel
        warning = checker.conflict(for: hotkey).map(Self.conflictText)
    }

    /// A combination was pressed while recording.
    public func record(_ hotkey: Hotkey) async {
        isRecording = false
        if let owner = checker.conflict(for: hotkey) {
            pendingConflict = (hotkey, owner)
            return
        }
        await save(hotkey)
    }

    public func confirmPending() async {
        guard let pending = pendingConflict else { return }
        pendingConflict = nil
        await save(pending.hotkey)
        warning = Self.conflictText(pending.owner)
    }

    public func discardPending() {
        pendingConflict = nil
    }

    private func save(_ hotkey: Hotkey) async {
        do {
            try await store.save(hotkey.settingValue)
            label = hotkey.displayLabel
            warning = nil
            apply(hotkey)
        } catch {
            warning = "couldn't save the shortcut. try again."
        }
    }

    public nonisolated static func conflictText(_ owner: String) -> String {
        "\(owner) already uses this shortcut. both will react."
    }
}
