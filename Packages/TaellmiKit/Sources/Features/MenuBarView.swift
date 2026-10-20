import Domain
import SwiftUI

/// The menu-bar window: one big record button, recent Entries, and a way into the Archive.
public struct MenuBarView: View {
    @Bindable var model: CaptureViewModel
    var appearance: AppearanceViewModel
    let hotkeyLabel: String
    let hotkeyWarning: String?
    let onOpenArchive: () -> Void
    let onOpenThought: (String) -> Void

    public init(
        model: CaptureViewModel, appearance: AppearanceViewModel, hotkeyLabel: String, hotkeyWarning: String?,
        onOpenArchive: @escaping () -> Void, onOpenThought: @escaping (String) -> Void
    ) {
        self.onOpenArchive = onOpenArchive
        self.onOpenThought = onOpenThought
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
                    .brandFont("text.label")
                    .brandStatus(.warning)
            }
            if model.isRecording {
                Text(model.livePreviewText.isEmpty ? "listening …" : model.livePreviewText)
                    .brandForeground(model.livePreviewText.isEmpty ? .quiet : .ink)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(8)
                    .brandFill(.field)
                    .brandAnimation(\.crossfade, value: model.livePreviewText)
                    .accessibilityLabel("live transcript")
            }
            if let error = model.errorMessage {
                Text(error).brandStatus(.problem)
            }
            Divider()
            if model.recentEntries.isEmpty {
                Text("no thoughts yet.").brandForeground(.quiet)
            } else {
                ForEach(model.recentEntries) { entry in
                    Button {
                        onOpenThought(entry.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.createdAt, format: .dateTime.day().month().hour().minute())
                                .brandFont("text.label").brandForeground(.quiet)
                            Text(CaptureViewModel.preview(of: entry)).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("opens this thought")
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
        .brandSurface(.panel)
        .textCase(appearance.swiftUICase)
    }

    private var recordButton: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            HStack {
                TalliView(mood: model.isRecording ? .listening(level: model.level) : .idle, entrance: nil)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    if let started = model.recordingStartedAt {
                        Text("listening")
                        Text(timerInterval: started...Date.distantFuture, countsDown: false)
                            .monospacedDigit().brandForeground(.quiet)
                    } else {
                        Text(model.isSaving ? "saving …" : "new thought")
                        Text(hotkeyLabel).brandFont("text.label").brandForeground(.quiet)
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
