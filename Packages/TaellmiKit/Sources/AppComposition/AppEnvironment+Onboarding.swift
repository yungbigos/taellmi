import Config
import Domain
import Features
import Foundation
import os

// What the first-launch onboarding asks of the assembled app.
extension AppEnvironment {
    // The models the assigned roles download (once each, in role order, with their size and how far they are on
    // this Mac), and the roles whose model comes with macOS.
    func voiceSetup() throws -> VoiceSetup {
        let installation = ModelInstallation(root: paths.models)
        let (downloads, builtIn) = try assignedModels()
        return VoiceSetup(
            downloads: downloads.map { role, model in
                VoiceModelStatus(
                    role: role, name: model.name, bytes: Int64(model.files.reduce(0) { $0 + $1.bytes }),
                    state: installation.isInstalled(model) ? .installed : voiceDownloads.states[model.id] ?? .missing)
            },
            builtIn: builtIn)
    }

    /// Starts downloading every assigned model from Hugging Face that isn't verified here yet, or follows the
    /// download already running: the voice setup on every change, until it ends (ADR 0016).
    func downloadVoiceModels() -> AsyncStream<VoiceSetup> {
        let logger = Logger(subsystem: "app.taellmi", category: "downloads")
        var items: [VoiceDownloads.Item] = []
        do {
            let installation = ModelInstallation(root: paths.models)
            for (_, model) in try assignedModels().downloads where !installation.isInstalled(model) {
                guard let provider = try ModelResolver.provider(of: model, in: database),
                    provider.kind == "huggingface",
                    let baseURL = provider.baseURL
                else {
                    logger.warning("\(model.id, privacy: .public) can't be downloaded: its provider isn't Hugging Face")
                    continue
                }
                items.append(VoiceDownloads.Item(model: model, baseURL: baseURL))
            }
        } catch {
            logger.error("Could not read which models to download: \(String(describing: error))")
        }
        let ticks = voiceDownloads.start(items)
        let (setups, continuation) = AsyncStream<VoiceSetup>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let following = Task { [weak self] in
            for await _ in ticks {
                if let setup = try? self?.voiceSetup() { continuation.yield(setup) }
            }
            if let setup = try? self?.voiceSetup() { continuation.yield(setup) }
            continuation.finish()
        }
        continuation.onTermination = { _ in following.cancel() }
        return setups
    }

    // The model each role is assigned to first: those with files to download (once each, in role order), and the
    // roles whose model comes with macOS.
    private func assignedModels() throws -> (downloads: [(ModelRole, ModelConfig)], builtIn: [ModelRole]) {
        var seen: Set<String> = []
        var downloads: [(ModelRole, ModelConfig)] = []
        var builtIn: [ModelRole] = []
        for role in ModelRole.allCases {
            guard let model = try ModelResolver.assigned(role, in: database) else { continue }
            guard !model.files.isEmpty else {
                builtIn.append(role)
                continue
            }
            guard seen.insert(model.id).inserted else { continue }
            downloads.append((role, model))
        }
        return (downloads, builtIn)
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
