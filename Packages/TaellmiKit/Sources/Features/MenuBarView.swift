import Domain
import SwiftUI

/// The menu-bar window: one big record button, recent Entries, and a way into the Archive.
public struct MenuBarView: View {
    @Bindable var model: CaptureViewModel
    var appearance: AppearanceViewModel
    let hotkeyLabel: String
    let hotkeyWarning: String?

    public init(
        model: CaptureViewModel, appearance: AppearanceViewModel, hotkeyLabel: String, hotkeyWarning: String?
    ) {
        self.model = model
        self.appearance = appearance
        self.hotkeyLabel = hotkeyLabel
        self.hotkeyWarning = hotkeyWarning
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            recordButton
            if let hotkeyWarning {
                Label(hotkeyWarning + " Ändern unter Einstellungen.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if model.isRecording {
                Text(model.livePreviewText.isEmpty ? "Ich höre zu …" : model.livePreviewText)
                    .font(.callout)
                    .foregroundStyle(model.livePreviewText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .animation(.easeOut(duration: 0.15), value: model.livePreviewText)
                    .accessibilityLabel("Live-Vorschau")
            }
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            Divider()
            if model.recentEntries.isEmpty {
                Text("Noch keine Einträge.").foregroundStyle(.secondary)
            } else {
                ForEach(model.recentEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.createdAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        Text(CaptureViewModel.preview(of: entry)).lineLimit(2)
                    }
                }
            }
            Divider()
            HStack {
                Button("Archiv im Finder zeigen") { NSWorkspace.shared.open(model.archiveFolder) }
                Spacer()
                SettingsLink { Text("Einstellungen …") }
                    // A menu-bar-only app must bring itself to the front, or the window opens behind others.
                    .simultaneousGesture(TapGesture().onEnded { NSApplication.shared.activate() })
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 340)
        .textCase(appearance.swiftUICase)
    }

    private var recordButton: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            HStack {
                Image(systemName: model.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(model.isRecording ? .red : .accentColor)
                VStack(alignment: .leading) {
                    if let started = model.recordingStartedAt {
                        Text("Aufnahme läuft")
                        Text(timerInterval: started...Date.distantFuture, countsDown: false)
                            .monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        Text(model.isSaving ? "Speichere …" : "Aufnahme starten")
                        Text(hotkeyLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSaving)
        .accessibilityLabel(model.isRecording ? "Aufnahme beenden" : "Aufnahme starten")
    }
}
