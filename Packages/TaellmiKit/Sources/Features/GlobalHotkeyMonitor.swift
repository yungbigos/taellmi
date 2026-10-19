import Carbon.HIToolbox
import Foundation
import os

/// Registers system-wide hotkeys through Carbon. Works inside the App Sandbox and needs no
/// Accessibility permission.
public final class GlobalHotkeyMonitor {
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "app.taellmi", category: "hotkey")

    public init() {}

    /// Registers `hotkey` under `id`, replacing whatever was registered under that id.
    public func register(_ hotkey: Hotkey, id: UInt32 = 1, action: @escaping @MainActor () -> Void) {
        installHandlerIfNeeded()
        unregister(id: id)
        actions[id] = action
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
