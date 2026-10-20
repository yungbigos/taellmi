import AppKit
import Foundation
import Observation
import SwiftUI

/// What the privacy tab needs. Implemented in the composition root.
public protocol PrivacySettings: Sendable {
    func locationDescription() async -> String
    func moveArchive(toParent parent: URL) async throws
    func exportPlain(to folder: URL) async throws -> Int
    func isWindowLocked() async -> Bool
    func setWindowLocked(_ on: Bool) async throws
    func pendingRecoveryKey() async -> String?
}

@Observable
public final class PrivacyViewModel {
    public private(set) var location = ""
    public private(set) var isLocked = false
    public private(set) var hasPendingRecoveryKey = false
    public private(set) var message: String?
    @ObservationIgnored private let settings: any PrivacySettings
    @ObservationIgnored private let restart: () -> Void

    public init(settings: any PrivacySettings, restart: @escaping () -> Void) {
        self.settings = settings
        self.restart = restart
    }

    public func load() async {
        location = await settings.locationDescription()
        isLocked = await settings.isWindowLocked()
        hasPendingRecoveryKey = await settings.pendingRecoveryKey() != nil
    }

    public func moveArchive(toParent parent: URL) async {
        message = "moving your thoughts …"
        do {
            try await settings.moveArchive(toParent: parent)
            message = "tällmi restarts and moves your thoughts there."
            restart()
        } catch {
            message = "couldn't move your thoughts there. nothing changed, so try another folder."
        }
    }

    public func export(to folder: URL) async {
        do {
            let count = try await settings.exportPlain(to: folder)
            message = "exported \(count) thoughts."
        } catch {
            message = "couldn't export. try another folder."
        }
    }

    public func setLocked(_ on: Bool) async {
        do {
            try await settings.setWindowLocked(on)
            isLocked = on
        } catch {
            message = "couldn't save the setting. try again."
        }
    }
}

struct PrivacySettingsView: View {
    @Bindable var model: PrivacyViewModel
    var showRecoveryKey: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("where your thoughts are stored") {
                    Text(model.location).lineLimit(1).truncationMode(.middle).brandForeground(.quiet)
                }
                Button("change …") {
                    if let folder = Self.chooseFolder(prompt: "store here") {
                        Task { await model.moveArchive(toParent: folder) }
                    }
                }
            } footer: {
                Text(
                    "any folder works, also icloud drive or a network drive. your thoughts stay encrypted there. if the folder already holds tällmi thoughts, tällmi opens those."
                )
            }
            Section("encryption") {
                LabeledContent("recovery key") {
                    if model.hasPendingRecoveryKey {
                        Button("show and confirm", action: showRecoveryKey)
                    } else {
                        Text("saved").brandForeground(.quiet)
                    }
                }
                Toggle(
                    "lock tällmi with touch id",
                    isOn: Binding(get: { model.isLocked }, set: { on in Task { await model.setLocked(on) } }))
            }
            Section {
                Button("export as plain files …") {
                    if let folder = Self.chooseFolder(prompt: "export here") { Task { await model.export(to: folder) } }
                }
            } footer: {
                Text("writes every thought as readable files, for example for obsidian. they are not encrypted there.")
            }
            if let message = model.message { Text(message).brandForeground(.quiet) }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 460, height: 420)
        .task { await model.load() }
    }

    private static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
