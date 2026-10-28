import AppKit
import Audio
import Domain
import Features
import Foundation
import SystemServices
import os

// The onboarding's view of the running app and of macOS.
final class LiveOnboardingServices: OnboardingServices {
    private let environment: AppEnvironment
    private let privacy: PrivacyViewModel
    private let logger = Logger(subsystem: "app.taellmi", category: "onboarding")

    init(environment: AppEnvironment, privacy: PrivacyViewModel) {
        self.environment = environment
        self.privacy = privacy
    }

    func voiceSetup() async -> VoiceSetup {
        (try? environment.voiceSetup()) ?? VoiceSetup(downloads: [], builtIn: [])
    }

    func downloadVoiceModels() -> AsyncStream<VoiceSetup> {
        environment.downloadVoiceModels()
    }

    func storageLocation() async -> String {
        guard environment.archiveRoot.standardizedFileURL != environment.paths.archive.standardizedFileURL else {
            return "on this mac, in your library"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "in " + environment.archiveRoot.path.replacingOccurrences(of: home, with: "~")
    }

    // The same move as in privacy settings: a folder that already holds tällmi thoughts is opened, and the
    // Recovery Key unlocks it after the restart.
    func useStorage(inside parent: URL) async -> String? {
        await privacy.moveArchive(toParent: parent)
        return privacy.message
    }

    func microphoneAccess() async -> MicrophoneAccess {
        switch MicrophonePermission.isAllowed {
        case true?: .allowed
        case false?: .denied
        case nil: .notAsked
        }
    }

    func requestMicrophone() async -> Bool {
        await MicrophonePermission.request()
    }

    func openMicrophoneSettings() {
        // A system URL that opens System Settings at the microphone list; no network involved.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func showModelsFolder() {
        let folder = environment.paths.models
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func confirmRecoveryKey(lastGroup: String, keepInKeychain: Bool) async throws -> Bool {
        try environment.confirmRecoveryKey(lastGroup: lastGroup, keepInKeychain: keepInKeychain)
    }

    func opensAtLogin() async -> Bool { LoginItem.isOn }

    func setOpensAtLogin(_ on: Bool) async -> Bool { LoginItem.set(on) }

    func usesContacts() async -> Bool {
        await environment.vocabularyModel.load()
        return environment.vocabularyModel.usesContacts
    }

    func setUsesContacts(_ on: Bool) async -> Bool {
        await environment.vocabularyModel.setUsesContacts(on)
        return environment.vocabularyModel.usesContacts
    }

    func importNotes(from urls: [URL]) async -> String? {
        guard !urls.isEmpty else { return nil }
        await environment.exploreModel.importNotes(from: urls)
        return takeImportMessage()
    }

    func importChats(from urls: [URL]) async -> String? {
        guard !urls.isEmpty else { return nil }
        await environment.exploreModel.importChats(from: urls)
        return takeImportMessage()
    }

    // The onboarding shows what the import did; the tällmi window shouldn't show it again later.
    private func takeImportMessage() -> String? {
        defer { environment.exploreModel.importMessage = nil }
        return environment.exploreModel.importMessage
    }

    func finish() async {
        do {
            try environment.finishOnboarding()
        } catch {
            logger.error("Could not remember that the onboarding is done: \(String(describing: error))")
        }
    }
}
