import SwiftUI

/// The composer fills the tällmi window (the window itself is not resized): tälli in the middle,
/// then only your text. Saves itself as you write; ⌘↩ or esc closes it.
struct ComposerView: View {
    @Bindable var model: ExploreViewModel
    @FocusState private var focused: Bool

    private var isListening: Bool { model.capture?.isRecording ?? false }

    var body: some View {
        VStack(spacing: 0) {
            TalliView(mood: isListening ? .listening(level: model.capture?.level ?? 0) : .idle)
                .frame(width: 72, height: 72)
                .padding(.top, 40)
            ZStack(alignment: .topLeading) {
                if isListening, model.composerText.isEmpty {
                    Text(spoken)
                        .font(.title3)
                        .foregroundStyle(spoken == Self.listening ? .secondary : .primary)
                        .lineSpacing(6)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.15), value: spoken)
                }
                TextEditor(text: $model.composerText)
                    .font(.title3)
                    .lineSpacing(6)
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
                    .font(.caption).foregroundStyle(.tertiary)
                Button("save") { Task { await model.finishComposing() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderless)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { focused = true }
    }

    private static let listening = "listening …"

    private var spoken: String {
        let text = model.capture?.livePreviewText ?? ""
        return text.isEmpty ? Self.listening : text
    }
}
