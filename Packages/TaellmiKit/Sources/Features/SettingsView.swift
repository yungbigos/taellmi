import AppKit
import Domain
import SwiftUI

/// The Settings window: General (tälli's shortcut, writing style) and Vocabulary.
public struct SettingsView: View {
    var hotkey: HotkeySettingsViewModel
    var exploreHotkey: HotkeySettingsViewModel
    var appearance: AppearanceViewModel
    var vocabulary: VocabularyViewModel

    public init(
        hotkey: HotkeySettingsViewModel, exploreHotkey: HotkeySettingsViewModel, appearance: AppearanceViewModel,
        vocabulary: VocabularyViewModel
    ) {
        self.hotkey = hotkey
        self.exploreHotkey = exploreHotkey
        self.appearance = appearance
        self.vocabulary = vocabulary
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(hotkey: hotkey, exploreHotkey: exploreHotkey, appearance: appearance)
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            VocabularySettingsView(model: vocabulary)
                .tabItem { Label("Vokabular", systemImage: "character.book.closed") }
        }
        .textCase(appearance.swiftUICase)
    }
}

struct GeneralSettingsView: View {
    @Bindable var hotkey: HotkeySettingsViewModel
    @Bindable var exploreHotkey: HotkeySettingsViewModel
    var appearance: AppearanceViewModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Tastenkürzel") {
                    HotkeyRecorder(model: hotkey)
                }
                if let warning = hotkey.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("tälli rufen")
            } footer: {
                Text("Mit diesem Kürzel erscheint tälli neben dem Mauszeiger und hört zu.")
            }
            Section("Archiv öffnen") {
                LabeledContent("Tastenkürzel") {
                    HotkeyRecorder(model: exploreHotkey)
                }
                if let warning = exploreHotkey.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section("Schreibweise") {
                Picker(
                    "Texte anzeigen",
                    selection: Binding(
                        get: { appearance.isLowercase },
                        set: { on in Task { await appearance.setLowercase(on) } })
                ) {
                    Text("Normal").tag(false)
                    Text("alles klein").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 400)
        .task {
            await hotkey.load()
            await exploreHotkey.load()
        }
        .alert(
            "Kürzel ist schon belegt",
            isPresented: Binding(
                get: { hotkey.pendingConflict != nil }, set: { if !$0 { hotkey.discardPending() } })
        ) {
            Button("Trotzdem verwenden") { Task { await hotkey.confirmPending() } }
            Button("Abbrechen", role: .cancel) { hotkey.discardPending() }
        } message: {
            if let pending = hotkey.pendingConflict {
                Text(HotkeySettingsViewModel.conflictText(pending.owner))
            }
        }
    }
}

/// Click, then press the new combination. Esc stops recording.
struct HotkeyRecorder: View {
    @Bindable var model: HotkeySettingsViewModel
    @State private var monitor: Any?

    var body: some View {
        Button {
            model.isRecording.toggle()
        } label: {
            Text(model.isRecording ? "Kombination drücken …" : model.label)
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
