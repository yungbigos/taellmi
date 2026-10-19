import Domain
import SwiftUI

/// The menu-bar window: one big record button, recent Entries, and a way into the Archive.
public struct MenuBarView: View {
    @Bindable var model: CaptureViewModel
    var appearance: AppearanceViewModel
    let hotkeyLabel: String
    let hotkeyWarning: String?
    let onOpenArchive: () -> Void

    public init(
        model: CaptureViewModel, appearance: AppearanceViewModel, hotkeyLabel: String, hotkeyWarning: String?,
        onOpenArchive: @escaping () -> Void
    ) {
        self.onOpenArchive = onOpenArchive
        self.model = model
        self.appearance = appearance
        self.hotkeyLabel = hotkeyLabel
        self.hotkeyWarning = hotkeyWarning
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            recordButton
            if let hotkeyWarning {
                Label(hotkeyWarning + " change it in settings.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if model.isRecording {
                Text(model.livePreviewText.isEmpty ? "listening …" : model.livePreviewText)
                    .font(.callout)
                    .foregroundStyle(model.livePreviewText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .animation(.easeOut(duration: 0.15), value: model.livePreviewText)
                    .accessibilityLabel("live transcript")
            }
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            Divider()
            if model.recentEntries.isEmpty {
                Text("no thoughts yet.").foregroundStyle(.secondary)
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
                Button("open tällmi", action: onOpenArchive)
                Spacer()
                SettingsLink { Text("settings …") }
                    // A menu-bar-only app must bring itself to the front, or the window opens behind others.
                    .simultaneousGesture(TapGesture().onEnded { NSApplication.shared.activate() })
                Button("quit") { NSApplication.shared.terminate(nil) }
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
                        Text("listening")
                        Text(timerInterval: started...Date.distantFuture, countsDown: false)
                            .monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        Text(model.isSaving ? "saving …" : "new thought")
                        Text(hotkeyLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSaving)
        .accessibilityLabel(model.isRecording ? "save thought" : "new thought")
    }
}
