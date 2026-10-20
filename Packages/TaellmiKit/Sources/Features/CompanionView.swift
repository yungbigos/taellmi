import SwiftUI

/// tälli next to the cursor, and a glass bubble with what it hears, a place to type, or "gespeichert".
struct CompanionView: View {
    @Bindable var model: CaptureViewModel
    var showsSaved: Bool
    var showsDiscarded: Bool
    /// Changes when the panel has become key and the input field should take focus.
    var focusRequest: Int
    var hint: String
    var onSubmitTyped: () -> Void
    var onOpenSaved: () -> Void
    @FocusState private var typingFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TalliView(mood: showsSaved ? .saved : model.isRecording ? .listening(level: model.level) : .idle)
                .frame(width: 64, height: 64)
            bubble
        }
        .padding(10)
        .frame(width: CompanionPanel.size.width, height: CompanionPanel.size.height, alignment: .topLeading)
    }

    @ViewBuilder private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsSaved {
                Button(action: onOpenSaved) {
                    // tälli's blink says it; the word is the quiet confirmation.
                    Text("saved.")
                }
                .buttonStyle(.plain)
            } else if showsDiscarded {
                Text("discarded.").foregroundStyle(.secondary)
            } else if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            } else {
                Text(model.livePreviewText.isEmpty ? "listening …" : model.livePreviewText)
                    .foregroundStyle(model.livePreviewText.isEmpty ? .secondary : .primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.15), value: model.livePreviewText)
                TextField("or type …", text: $model.typedText)
                    .textFieldStyle(.plain)
                    .focused($typingFocused)
                    .onSubmit(onSubmitTyped)
                    .task(id: focusRequest) {
                        // One run-loop turn later the window is key, so the focus request sticks.
                        await Task.yield()
                        typingFocused = true
                    }
            }
            Spacer(minLength: 0)
            Text(hint)
                .brandFont("text.whisper")
                .foregroundStyle(.tertiary)
        }
        .brandFont("text.body")
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
