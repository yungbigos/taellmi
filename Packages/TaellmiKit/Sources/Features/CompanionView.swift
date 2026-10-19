import SwiftUI

/// tälli next to the cursor: the orb, and a bubble with what it hears, a place to type, or "gespeichert".
struct CompanionView: View {
    @Bindable var model: CaptureViewModel
    var showsSaved: Bool
    var hint: String
    var onSubmitTyped: () -> Void
    @FocusState private var typingFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CompanionOrb(level: model.level, isListening: model.isRecording)
                .frame(width: 64, height: 64)
            bubble
        }
        .padding(10)
        .frame(width: CompanionPanel.size.width, height: CompanionPanel.size.height, alignment: .topLeading)
    }

    @ViewBuilder private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsSaved {
                Label("Gespeichert", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                Text(model.livePreviewText.isEmpty ? "Ich höre zu …" : model.livePreviewText)
                    .foregroundStyle(model.livePreviewText.isEmpty ? .secondary : .primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.15), value: model.livePreviewText)
                TextField("… oder tippen", text: $model.typedText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($typingFocused)
                    .onSubmit(onSubmitTyped)
                    .onAppear { typingFocused = true }
            }
            Spacer(minLength: 0)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
