import AppKit
import Observation
import SwiftUI

/// Shown once after setup: the Recovery Key, to save somewhere safe and confirm.
@Observable
public final class RecoveryKeyViewModel {
    public let recoveryKey: String
    public var typedGroup = ""
    public var keepInKeychain = false
    public private(set) var message: String?
    public private(set) var isDone = false
    @ObservationIgnored private let confirmAction: (String, Bool) async throws -> Bool

    public init(recoveryKey: String, confirm: @escaping (String, Bool) async throws -> Bool) {
        self.recoveryKey = recoveryKey
        self.confirmAction = confirm
    }

    public func confirm() async {
        do {
            if try await confirmAction(typedGroup, keepInKeychain) {
                isDone = true
                message = nil
            } else {
                message = "that doesn't match the last group. check and try again."
            }
        } catch {
            message = "couldn't save that. try again."
        }
    }
}

/// On a new Mac: unlock the Archive with its Recovery Key.
@Observable
public final class UnlockArchiveViewModel {
    public var typed = ""
    public private(set) var message: String?
    public private(set) var isUnlocked = false
    @ObservationIgnored private let unlockAction: (String) async throws -> Bool

    public init(unlock: @escaping (String) async throws -> Bool) {
        self.unlockAction = unlock
    }

    public func unlock() async {
        if (try? await unlockAction(typed)) == true {
            isUnlocked = true
            message = nil
        } else {
            message = "that recovery key doesn't fit this archive. check it and try again."
        }
    }
}

public struct RecoveryKeyView: View {
    @Bindable var model: RecoveryKeyViewModel
    var onDone: () -> Void

    public init(model: RecoveryKeyViewModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("your recovery key").font(.title2)
            Text(
                "your thoughts are encrypted. with this key you can open them on another mac, or if this mac's keychain is lost. keep it somewhere safe, for example in your password manager or on paper."
            )
            .foregroundStyle(.secondary)
            Text(model.recoveryKey)
                .font(.title3.monospaced())
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
                    .onSubmit { Task { await model.confirm() } }
                Button("done") { Task { await model.confirm() } }
                    .keyboardShortcut(.defaultAction)
            }
            if let message = model.message { Text(message).foregroundStyle(.orange) }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: model.isDone) { _, done in if done { onDone() } }
    }

    private func print(_ key: String) {
        let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 480, height: 200))
        text.string = "tällmi recovery key\n\n\(key)\n\nkeep this somewhere safe."
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        NSPrintOperation(view: text).run()
    }
}

public struct UnlockArchiveView: View {
    @Bindable var model: UnlockArchiveViewModel
    var onUnlocked: () -> Void

    public init(model: UnlockArchiveViewModel, onUnlocked: @escaping () -> Void) {
        self.model = model
        self.onUnlocked = onUnlocked
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("unlock your thoughts").font(.title2)
            Text("this mac doesn't know the key to your thoughts yet. enter your recovery key.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("recovery key", text: $model.typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit { Task { await model.unlock() } }
                Button("unlock") { Task { await model.unlock() } }
                    .keyboardShortcut(.defaultAction)
            }
            if let message = model.message { Text(message).foregroundStyle(.orange) }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: model.isUnlocked) { _, unlocked in if unlocked { onUnlocked() } }
    }
}

/// A small standalone window for one-off panels (recovery key, unlock).
public enum PanelWindow {
    @discardableResult
    public static func show(title: String, @ViewBuilder content: () -> some View) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
