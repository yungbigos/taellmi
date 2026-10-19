import SwiftUI

/// The composer fills the tällmi window (the window itself is not resized): tälli in the middle,
/// then only your text. Saves itself as you write; ⌘↩ or esc closes it.
struct ComposerView: View {
    @Bindable var model: ExploreViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TalliView(mood: .idle)
                .frame(width: 72, height: 72)
                .padding(.top, 40)
            TextEditor(text: $model.composerText)
                .font(.title3)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(maxWidth: 720)
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .onKeyPress(.escape) {
                    finish()
                    return .handled
                }
            HStack {
                Spacer()
                Text("⌘↩ done · esc close").font(.caption).foregroundStyle(.tertiary)
                Button("done", action: finish)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderless)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { focused = true }
    }

    private func finish() {
        Task { await model.finishComposing() }
    }
}
