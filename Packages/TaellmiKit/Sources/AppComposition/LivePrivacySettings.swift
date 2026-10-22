import Config
import Domain
import Features
import Foundation
import LocalAuthentication
import Persistence

/// Privacy settings backed by the Archive location, the vault and config.
nonisolated struct LivePrivacySettings: PrivacySettings {
    let archiveRoot: URL
    let files: EntryFileStore
    let settings: SettingsStore
    let editor: ConfigEditor
    let pending: @Sendable () -> String?
    let library: LiveExploreLibrary

    func locationDescription() async -> String {
        archiveRoot.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    func moveArchive(toParent parent: URL) async throws {
        try ArchiveLocation.scheduleMove(toParent: parent, current: archiveRoot, editor: editor)
    }

    func exportPlain(to folder: URL) async throws -> Int {
        try PlainExport.export(files, to: folder)
    }

    func importNotes(from urls: [URL]) async throws -> NoteImportReport {
        try await library.importNotes(from: urls)
    }

    func importChats(from urls: [URL]) async throws -> ChatImportReport {
        try await library.importChats(from: urls)
    }

    func isWindowLocked() async -> Bool { (try? settings.bool(SettingKeys.lockWindow)) ?? false }

    func setWindowLocked(_ on: Bool) async throws {
        try editor.setSetting(SettingKeys.lockWindow, to: .bool(on))
    }

    func pendingRecoveryKey() async -> String? { pending() }
}

/// Touch ID (or your Mac password) before the window opens, when the lock setting is on.
nonisolated enum WindowLock {
    static func authorize(settings: SettingsStore) async -> Bool {
        guard (try? settings.bool(SettingKeys.lockWindow)) == true else { return true }
        return
            (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open your thoughts"))
            ?? false
    }
}
