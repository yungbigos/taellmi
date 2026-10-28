import Domain
import Features
import Foundation
import TestSupport
import Testing

@Suite("Downloading what tällmi needs, from the voice step")
struct OnboardingDownloadTests {
    typealias FakeServices = OnboardingModelTests.FakeServices
    static let english = Locale(identifier: "en_US")

    static func speech(_ state: VoiceModelState) -> VoiceModelStatus {
        VoiceModelStatus(role: .transcription, name: "Speech Model", bytes: 632_169_729, state: state)
    }

    static func meaning(_ state: VoiceModelState) -> VoiceModelStatus {
        VoiceModelStatus(role: .embed, name: "Meaning Model", bytes: 644_631_738, state: state)
    }

    static func setup(_ speech: VoiceModelState, _ meaning: VoiceModelState) -> VoiceSetup {
        VoiceSetup(downloads: [Self.speech(speech), Self.meaning(meaning)], builtIn: [.liveTranscription])
    }

    @Test(
        "sizes read the way the design shows them",
        arguments: [(632_169_729, "632 MB"), (644_631_738, "645 MB"), (1_276_801_467, "1.3 GB")]
            as [(Int64, String)])
    func sizes(bytes: Int64, text: String) {
        #expect(OnboardingModel.size(bytes, locale: Self.english) == text)
    }

    @Test("the button names everything still missing: download 1.3 GB")
    func downloadTitle() async throws {
        let services = FakeServices()
        services.setup = Self.setup(.missing, .missing)
        let (model, _, _, temp) = try await OnboardingModelTests().makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        #expect(model.missingBytes == 1_276_801_467)
        #expect(OnboardingModel.downloadTitle(missing: model.missingBytes, locale: Self.english) == "download 1.3 GB")
    }

    @Test(
        "each row says how far it is",
        arguments: [
            (VoiceModelState.missing, "632 MB"),
            (.waiting, "next · 632 MB"),
            (.downloading(received: 214_000_000), "214 of 632 MB"),
            (.installed, "on this mac"),
            (.failed, "didn't finish"),
        ])
    func rowLine(state: VoiceModelState, line: String) {
        #expect(OnboardingModel.sizeLine(for: Self.speech(state), locale: Self.english) == line)
    }

    @Test("download gets what is missing; then it is on this mac, and spoken thoughts get their text")
    func downloads() async throws {
        let services = FakeServices()
        services.setup = Self.setup(.missing, .missing)
        services.downloadUpdates = [
            Self.setup(.downloading(received: 214_000_000), .waiting),
            Self.setup(.installed, .downloading(received: 0)),
            Self.setup(.installed, .installed),
        ]
        let (model, _, _, temp) = try await OnboardingModelTests().makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        #expect(!model.canHearYet)

        await model.download()

        #expect(services.downloadStarts == 1)
        #expect(model.voiceModels.map(\.isInstalled) == [true, true])
        #expect(model.canHearYet)
        #expect(!model.isDownloading)
    }

    @Test("while it downloads, tälli thinks, and you can go on; the step after still learns when it's done")
    func goOnWhileDownloading() async throws {
        let services = FakeServices()
        services.setup = Self.setup(.missing, .missing)
        services.downloadUpdates = [Self.setup(.downloading(received: 214_000_000), .waiting)]
        services.holdsDownload = true
        let (model, _, _, temp) = try await OnboardingModelTests().makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        OnboardingModelTests().advance(model, to: .voice)

        let following = Task { await model.download() }
        try await waitUntil { model.isDownloading }
        #expect(model.talliIsThinking)
        model.next()
        #expect(model.step == .microphone)
        #expect(!model.talliIsThinking, "tälli thinks on the voice step only")

        services.download?.yield(Self.setup(.installed, .installed))
        services.download?.finish()
        await following.value
        #expect(model.canHearYet)
        #expect(!model.isDownloading)
    }

    @Test("pressing download again while it runs doesn't start a second download")
    func onlyOnce() async throws {
        let services = FakeServices()
        services.setup = Self.setup(.missing, .missing)
        services.downloadUpdates = [Self.setup(.downloading(received: 0), .waiting)]
        services.holdsDownload = true
        let (model, _, _, temp) = try await OnboardingModelTests().makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }

        let following = Task { await model.download() }
        try await waitUntil { model.isDownloading }
        await model.download()
        #expect(services.downloadStarts == 1)

        services.download?.finish()
        await following.value
    }

    @Test("a download that stops says so, and trying again starts it anew")
    func failedThenAgain() async throws {
        let services = FakeServices()
        services.setup = Self.setup(.missing, .missing)
        services.downloadUpdates = [Self.setup(.failed, .installed)]
        let (model, _, _, temp) = try await OnboardingModelTests().makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }

        await model.download()
        #expect(model.downloadFailed)
        #expect(!model.isDownloading)
        #expect(!model.talliIsThinking)

        services.downloadUpdates = [Self.setup(.installed, .installed)]
        await model.download()
        #expect(services.downloadStarts == 2)
        #expect(!model.downloadFailed)
        #expect(model.canHearYet)
    }
}
