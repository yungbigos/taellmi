import SwiftUI

/// The composer fills the tällmi window (the window itself is not resized): tälli in the middle,
/// then only your text. Saves itself as you write; ⌘↩ or esc closes it.
struct ComposerView: View {
    @Bindable var model: ExploreViewModel
    @FocusState private var focused: Bool

    private var isListening: Bool { model.capture?.isRecording ?? false }

    var body: some View {
        VStack(spacing: 0) {
            TalliView(mood: isListening ? .listening(level: model.capture?.level ?? 0) : .idle, entrance: .roll)
                .frame(width: 72, height: 72)
                .padding(.top, 40)
            ZStack(alignment: .topLeading) {
                if isListening, model.composerText.isEmpty {
                    Text(spoken)
                        .brandFont("text.thought")
                        .brandForeground(spoken == Self.listening ? .quiet : .ink)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .brandAnimation(\.crossfade, value: spoken)
                }
                TextEditor(text: $model.composerText)
                    .brandFont("text.thought")
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .onChange(of: model.composerText) { Task { await model.typingStarted() } }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .onKeyPress(.escape) {
                Task { await model.closeComposer() }
                return .handled
            }
            HStack {
                Spacer()
                Text(isListening ? "speak or type · ⌘↩ save · esc discard" : "⌘↩ save · esc close")
                    .brandFont("text.label").brandForeground(.quiet)
                Button("save") { Task { await model.finishComposing() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderless)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .brandSurface(.reading)
        .task { focused = true }
    }

    private static let listening = "listening …"

    private var spoken: String {
        let text = model.capture?.livePreviewText ?? ""
        return text.isEmpty ? Self.listening : text
    }
}
