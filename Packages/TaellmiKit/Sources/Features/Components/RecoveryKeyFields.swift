import AppKit
import SwiftUI

// The new Recovery Key and what you do with it: copy, print, keep in the keychain, confirm the last group.
// Shown in its own panel and in the onboarding.
struct RecoveryKeyFields: View {
    @Bindable var model: RecoveryKeyViewModel
    var confirm: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                "your thoughts are encrypted. with this key you can open them on another mac, or if this mac's keychain is lost. keep it somewhere safe, for example in your password manager or on paper."
            )
            .brandForeground(.quiet)
            .fixedSize(horizontal: false, vertical: true)
            Text(model.recoveryKey)
                // Monospaced on purpose: every character of the key must be told apart (0 and O, 1 and l).
                .font(.title3.monospaced())
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity)
                .brandFill(.field)
            HStack {
                Button("copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.recoveryKey, forType: .string)
                }
                Button("print") { print(model.recoveryKey) }
                Spacer()
            }
            Toggle("also keep it in the keychain on this mac", isOn: $model.keepInKeychain)
            HStack {
                TextField("type the last group to confirm", text: $model.typedGroup)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await confirm() } }
                Button("done") { Task { await confirm() } }
                    .keyboardShortcut(.defaultAction)
            }
            if let message = model.message { Text(message).brandStatus(.warning) }
        }
    }

    private func print(_ key: String) {
        let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 200))
        text.string = "tällmi recovery key\n\n\(key)\n\nkeep this somewhere safe."
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        NSPrintOperation(view: text).run()
    }
}
