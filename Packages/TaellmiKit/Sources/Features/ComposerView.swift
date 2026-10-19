import AppKit
import SwiftUI

/// The full-window composer: only your text. Saves itself as you write; ⌘↩ or esc closes it.
struct ComposerView: View {
    @Bindable var model: ExploreViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.composerText)
                .font(.title3)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(maxWidth: 720)
                .padding(.horizontal, 40)
                .padding(.top, 60)
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

/// Puts the window into macOS full screen while composing, and back out afterwards.
struct ComposerFullScreen: ViewModifier {
    var isComposing: Bool
    var enabled: Bool
    @State private var enteredFullScreen = false

    func body(content: Content) -> some View {
        content.onChange(of: isComposing) { _, composing in
            guard enabled, let window = NSApplication.shared.keyWindow else { return }
            let isFullScreen = window.styleMask.contains(.fullScreen)
            if composing, !isFullScreen {
                enteredFullScreen = true
                window.toggleFullScreen(nil)
            } else if !composing, enteredFullScreen, isFullScreen {
                enteredFullScreen = false
                window.toggleFullScreen(nil)
            }
        }
    }
}
