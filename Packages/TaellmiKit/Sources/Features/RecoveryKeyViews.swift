import AppKit
import Domain
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
            Text("your recovery key").brandFont("display.heading")
            RecoveryKeyFields(model: model) { await model.confirm() }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: model.isDone) { _, done in if done { onDone() } }
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
            Text("unlock your thoughts").brandFont("display.heading")
            Text("this mac doesn't know the key to your thoughts yet. enter your recovery key.")
                .brandForeground(.quiet)
            HStack {
                TextField("recovery key", text: $model.typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit { Task { await model.unlock() } }
                Button("unlock") { Task { await model.unlock() } }
                    .keyboardShortcut(.defaultAction)
            }
            if let message = model.message { Text(message).brandStatus(.warning) }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: model.isUnlocked) { _, unlocked in if unlocked { onUnlocked() } }
    }
}

/// A small standalone window for one-off panels (recovery key, unlock).
public enum PanelWindow {
    @discardableResult
    public static func show(
        title: String, brand: BrandTokens?, @ViewBuilder content: () -> some View
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: content()
                .background { BrandSurfaceBackground(kind: .panel, radius: nil).ignoresSafeArea() }
                .brandStyle(brand))
        window.center()
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
