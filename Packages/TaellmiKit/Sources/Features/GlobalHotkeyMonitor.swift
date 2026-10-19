import Carbon.HIToolbox
import Foundation
import os

/// Registers one system-wide hotkey through Carbon. Works inside the App Sandbox and needs no
/// Accessibility permission.
public final class GlobalHotkeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private let logger = Logger(subsystem: "app.taellmi", category: "hotkey")

    public init() {}

    /// Replaces any previously registered hotkey.
    public func register(_ hotkey: Hotkey, action: @escaping @MainActor () -> Void) {
        unregister()
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.action?() }
                return noErr
            }, 1, &spec, context, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x544C_4D45), id: 1)  // "TLME"
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { logger.error("Hotkey registration failed with status \(status)") }
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
