import Config
import Domain
import Features
import Foundation
import os

// What the first-launch onboarding asks of the assembled app.
extension AppEnvironment {
    // The models the assigned roles download (once each, in role order, with their size and whether they are
    // verified here), and the roles whose model comes with macOS.
    func voiceSetup() throws -> VoiceSetup {
        let installation = ModelInstallation(root: paths.models)
        var seen: Set<String> = []
        var downloads: [VoiceModelStatus] = []
        var builtIn: [ModelRole] = []
        for role in ModelRole.allCases {
            guard let model = try ModelResolver.assigned(role, in: database) else { continue }
            guard !model.files.isEmpty else {
                builtIn.append(role)
                continue
            }
            guard seen.insert(model.id).inserted else { continue }
            downloads.append(
                VoiceModelStatus(
                    role: role, name: model.name, bytes: Int64(model.files.reduce(0) { $0 + $1.bytes }),
                    isInstalled: installation.isInstalled(model)))
        }
        return VoiceSetup(downloads: downloads, builtIn: builtIn)
    }

    // Where the onboarding's tälli sizes come from.
    func onboardingTalliSizes() throws -> OnboardingTalliSizes {
        OnboardingTalliSizes(
            hello: try settings.number(SettingKeys.onboardingTalliHello),
            corner: try settings.number(SettingKeys.onboardingTalliCorner),
            peek: try settings.number(SettingKeys.onboardingTalliPeek))
    }

    // Only a fresh tällmi opens the onboarding. An Archive that already has thoughts never will: that is
    // remembered, so emptying it later doesn't bring the onboarding back.
    func shouldOpenOnboarding() async -> Bool {
        let completed = (try? settings.bool(SettingKeys.onboardingCompleted)) ?? true
        guard !completed else { return false }
        let logger = Logger(subsystem: "app.taellmi", category: "onboarding")
        // When the Archive can't be read, it may well have thoughts: don't open the onboarding over them.
        guard let recent = try? await journal.recentEntries(limit: 1) else { return false }
        let hasThoughts = !recent.isEmpty
        if hasThoughts {
            do {
                try finishOnboarding()
            } catch {
                logger.error("Could not remember that the onboarding is done: \(String(describing: error))")
            }
        }
        return OnboardingModel.shouldOpen(completed: completed, hasThoughts: hasThoughts)
    }

    func finishOnboarding() throws {
        try ConfigEditor(database: database).setSetting(SettingKeys.onboardingCompleted, to: .bool(true))
    }
}
