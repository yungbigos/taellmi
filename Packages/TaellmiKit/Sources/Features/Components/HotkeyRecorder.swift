import AppKit
import Domain
import SwiftUI

extension View {
    // Asks before taking a combination macOS or another command already uses.
    func shortcutConflictAlert(_ model: HotkeySettingsViewModel) -> some View {
        alert(
            "this shortcut is taken",
            isPresented: Binding(get: { model.pendingConflict != nil }, set: { if !$0 { model.discardPending() } })
        ) {
            Button("use it anyway") { Task { await model.confirmPending() } }
            Button("cancel", role: .cancel) { model.discardPending() }
        } message: {
            if let pending = model.pendingConflict {
                Text(HotkeySettingsViewModel.conflictText(pending.owner))
            }
        }
    }
}

// Click, then press the new combination. Esc stops recording. Used in settings and the onboarding.
struct HotkeyRecorder: View {
    @Bindable var model: HotkeySettingsViewModel
    // What the button says when not recording; the current shortcut if nil.
    var title: String?
    @State private var monitor: Any?

    var body: some View {
        Button {
            model.isRecording.toggle()
        } label: {
            Text(model.isRecording ? "press keys …" : title ?? model.label)
                .monospacedDigit()
                .frame(minWidth: 140)
        }
        .onChange(of: model.isRecording) { _, recording in
            recording ? startMonitoring() : stopMonitoring()
        }
        .onDisappear { stopMonitoring() }
    }

    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                model.isRecording = false
                return nil
            }
            let flags = event.modifierFlags
            if let hotkey = Hotkey(
                keyCode: Int(event.keyCode), command: flags.contains(.command), option: flags.contains(.option),
                control: flags.contains(.control), shift: flags.contains(.shift))
            {
                Task { await model.record(hotkey) }
            }
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
