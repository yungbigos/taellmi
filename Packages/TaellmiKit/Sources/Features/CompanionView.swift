import SwiftUI

/// tälli where you called it, and a glass bubble with what it hears, a place to type, or "saved.".
/// tälli watches the cursor from there; dragging tälli moves the panel, clicking it pokes it.
struct CompanionView: View {
    @Bindable var model: CaptureViewModel
    var showsSaved: Bool
    var showsDiscarded: Bool
    /// Changes when the panel has become key and the input field should take focus.
    var focusRequest: Int
    var hint: String
    /// False while the panel is hidden, so tälli stops drawing.
    var isShown: Bool
    /// The pointer in the panel's SwiftUI global coordinates, for tälli to watch.
    var cursor: @MainActor () -> CGPoint?
    var talliSize: CGFloat
    var panelSize: CGSize
    /// Clicks on tälli and moments it was carried, counted by the controller.
    var pokes: Int
    var stirs: Int
    var onSubmitTyped: () -> Void
    var onOpenSaved: () -> Void
    /// Called repeatedly while you press on tälli and move, then once when you let go; the controller
    /// decides whether that was a drag or a poke.
    var onDrag: () -> Void
    var onDragEnded: () -> Void
    @FocusState private var typingFocused: Bool
    @State private var keystrokes = 0
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TalliView(
                mood: showsSaved ? .saved : model.isRecording ? .listening(level: model.level) : .idle,
                cursor: cursor, pokes: pokes, stirs: stirs + keystrokes, paused: !isShown
            )
            .frame(width: talliSize, height: talliSize)
            // One gesture for both, so letting go after a drag never also counts as a poke.
            .gesture(press, including: brand?.motion.attention == nil ? .none : .all)
            bubble
        }
        .padding(10)
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .onChange(of: model.typedText) { keystrokes += 1 }
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in onDrag() }
            .onEnded { _ in onDragEnded() }
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
                Text(error).brandStatus(.problem)
            } else {
                Text(model.livePreviewText.isEmpty ? "listening …" : model.livePreviewText)
                    .foregroundStyle(model.livePreviewText.isEmpty ? .secondary : .primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandAnimation(\.crossfade, value: model.livePreviewText)
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
                // On glass over any app, vibrant system colours keep text readable; fixed brand colours can't.
                .foregroundStyle(.secondary)
        }
        .brandFont("text.body")
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Anywhere in the bubble puts you in the text field, not only the one line it occupies.
        .contentShape(.rect)
        .onTapGesture { typingFocused = true }
        .brandSurface(.bubble, radius: .bubble)
    }
}
