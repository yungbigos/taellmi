import AppKit
import Domain
import SwiftUI

/// The Settings window: General (tälli's shortcut, writing style) and Vocabulary.
public struct SettingsView: View {
    var hotkey: HotkeySettingsViewModel
    var exploreHotkey: HotkeySettingsViewModel
    var appearance: AppearanceViewModel
    var vocabulary: VocabularyViewModel
    var commandShortcuts: [(Command, HotkeySettingsViewModel)]
    var privacy: PrivacyViewModel
    var showRecoveryKey: () -> Void

    public init(
        hotkey: HotkeySettingsViewModel, exploreHotkey: HotkeySettingsViewModel, appearance: AppearanceViewModel,
        vocabulary: VocabularyViewModel, commandShortcuts: [(Command, HotkeySettingsViewModel)],
        privacy: PrivacyViewModel, showRecoveryKey: @escaping () -> Void
    ) {
        self.privacy = privacy
        self.showRecoveryKey = showRecoveryKey
        self.commandShortcuts = commandShortcuts
        self.hotkey = hotkey
        self.exploreHotkey = exploreHotkey
        self.appearance = appearance
        self.vocabulary = vocabulary
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(hotkey: hotkey, exploreHotkey: exploreHotkey, appearance: appearance)
                .tabItem { Label("general", systemImage: "gearshape") }
            VocabularySettingsView(model: vocabulary)
                .tabItem { Label("spellings", systemImage: "character.book.closed") }
            ShortcutSettingsView(rows: commandShortcuts)
                .tabItem { Label("shortcuts", systemImage: "keyboard") }
            PrivacySettingsView(model: privacy, showRecoveryKey: showRecoveryKey)
                .tabItem { Label("privacy", systemImage: "lock") }
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
                LabeledContent("hotkey") {
                    HotkeyRecorder(model: hotkey)
                }
                if let warning = hotkey.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("call tälli")
            } footer: {
                Text("tälli appears next to your cursor and listens.")
            }
            Section("open tällmi") {
                LabeledContent("hotkey") {
                    HotkeyRecorder(model: exploreHotkey)
                }
                if let warning = exploreHotkey.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section("appearance") {
                Picker(
                    "show your thoughts",
                    selection: Binding(
                        get: { appearance.isLowercase },
                        set: { on in Task { await appearance.setLowercase(on) } })
                ) {
                    Text("as written").tag(false)
                    Text("all lowercase").tag(true)
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
            "this shortcut is taken",
            isPresented: Binding(
                get: { hotkey.pendingConflict != nil }, set: { if !$0 { hotkey.discardPending() } })
        ) {
            Button("use it anyway") { Task { await hotkey.confirmPending() } }
            Button("cancel", role: .cancel) { hotkey.discardPending() }
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
            Text(model.isRecording ? "press keys …" : model.label)
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

/// Every command with its shortcut. Click a shortcut, then press the new keys.
struct ShortcutSettingsView: View {
    var rows: [(Command, HotkeySettingsViewModel)]

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.0) { command, model in
                    ShortcutRow(title: command.title, model: model)
                }
            } footer: {
                Text("these work while the tällmi window is in front.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}

private struct ShortcutRow: View {
    let title: String
    @Bindable var model: HotkeySettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HotkeyRecorder(model: model)
            }
            if let warning = model.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task { await model.load() }
        .alert(
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
