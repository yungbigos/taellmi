import Carbon.HIToolbox
import Domain
import Foundation
import os

/// Registers system-wide hotkeys through Carbon. Works inside the App Sandbox and needs no
/// Accessibility permission.
public final class GlobalHotkeyMonitor {
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    /// Every hotkey asked for, so they can come back after a pause.
    private var wanted: [UInt32: Hotkey] = [:]
    private var isPaused = false
    private var handlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "app.taellmi", category: "hotkey")

    public init() {}

    /// Registers `hotkey` under `id`, replacing whatever was registered under that id.
    public func register(_ hotkey: Hotkey, id: UInt32 = 1, action: @escaping @MainActor () -> Void) {
        installHandlerIfNeeded()
        unregister(id: id)
        actions[id] = action
        wanted[id] = hotkey
        if !isPaused { activate(hotkey, id: id) }
    }

    /// Lets every combination through to the app, e.g. while you record a new shortcut.
    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        for ref in hotKeys.values { UnregisterEventHotKey(ref) }
        hotKeys = [:]
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        for (id, hotkey) in wanted { activate(hotkey, id: id) }
    }

    private func activate(_ hotkey: Hotkey, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x544C_4D45), id: id)  // "TLME"
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeys[id] = ref
        } else {
            logger.error("Hotkey registration failed with status \(status)")
        }
    }

    public func unregister(id: UInt32) {
        if let ref = hotKeys.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
        wanted[id] = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.actions[hotKeyID.id]?() }
                return noErr
            }, 1, &spec, context, &handlerRef)
    }
}
