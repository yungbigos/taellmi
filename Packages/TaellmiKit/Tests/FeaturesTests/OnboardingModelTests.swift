import Domain
import Features
import Foundation
import Observation
import Synchronization
import TestSupport
import Testing

@Suite("The first launch, step by step")
struct OnboardingModelTests {
    /// Answers the way macOS and the app would, from fixed values; counts what it was asked to do.
    final class FakeServices: OnboardingServices {
        var setup = VoiceSetup(
            downloads: [
                VoiceModelStatus(role: .transcription, name: "Speech Model", bytes: 632_000_000, isInstalled: false),
                VoiceModelStatus(role: .embed, name: "Meaning Model", bytes: 645_000_000, isInstalled: true),
            ],
            builtIn: [.liveTranscription, .summary])
        var microphone: MicrophoneAccess = .notAsked
        var grantsMicrophone = true
        var keyGroup = "V6JB"
        var loginItemWorks = true
        var importMessage: String? = "2 thoughts imported."
        var storage = "on this mac, in your library"
        var storageRefusal: String?
        private(set) var keyConfirmations: [(String, Bool)] = []
        private(set) var finishCount = 0
        private(set) var openedMicrophoneSettings = false
        private(set) var storageParents: [URL] = []

        func voiceSetup() async -> VoiceSetup { setup }
        func microphoneAccess() async -> MicrophoneAccess { microphone }
        func requestMicrophone() async -> Bool {
            microphone = grantsMicrophone ? .allowed : .denied
            return grantsMicrophone
        }
        func openMicrophoneSettings() { openedMicrophoneSettings = true }
        func showModelsFolder() {}
        func confirmRecoveryKey(lastGroup: String, keepInKeychain: Bool) async throws -> Bool {
            keyConfirmations.append((lastGroup, keepInKeychain))
            return lastGroup == keyGroup
        }
        func storageLocation() async -> String { storage }
        func useStorage(inside parent: URL) async -> String? {
            storageParents.append(parent)
            return storageRefusal
        }
        func opensAtLogin() async -> Bool { false }
        func setOpensAtLogin(_ on: Bool) async -> Bool { loginItemWorks ? on : false }
        func usesContacts() async -> Bool { false }
        func setUsesContacts(_ on: Bool) async -> Bool { on }
        func importNotes(from urls: [URL]) async -> String? { urls.isEmpty ? nil : importMessage }
        func importChats(from urls: [URL]) async -> String? { urls.isEmpty ? nil : importMessage }
        func finish() async { finishCount += 1 }
    }

    private func makeModel(
        services: FakeServices = FakeServices(), recoveryKey: String? = "7KQF-M29D-XW4R-V6JB",
        journal: FakeJournal = FakeJournal(), preview: (any LivePreviewing)? = nil, liveChunks: [AudioSamples] = []
    ) async throws -> (OnboardingModel, FakeServices, CaptureViewModel, TemporaryDirectory) {
        let temp = try TemporaryDirectory()
        let capture = CaptureViewModel(
            recorder: FakeRecorder(folder: temp.url, liveChunks: liveChunks), journal: journal, preview: preview)
        capture.startObservingEntries()
        let shortcut = HotkeySettingsViewModel(
            store: HotkeySettingsViewModelTests.FakeStore("control+option+t"),
            checker: HotkeySettingsViewModelTests.FakeChecker(taken: []))
        let model = OnboardingModel(
            services: services, capture: capture, shortcut: shortcut, finishKey: "↩", recoveryKey: recoveryKey)
        await model.load()
        return (model, services, capture, temp)
    }

    /// Walks forward until `step` (or gives up after every step).
    private func advance(_ model: OnboardingModel, to step: OnboardingStep) {
        for _ in 0..<10 where model.step != step { model.next() }
    }

    @Test(
        "only a fresh tällmi opens the onboarding: not one with thoughts, not one that finished it",
        arguments: [(false, false, true), (false, true, false), (true, false, false), (true, true, false)])
    func whoSeesIt(completed: Bool, hasThoughts: Bool, opens: Bool) {
        #expect(OnboardingModel.shouldOpen(completed: completed, hasThoughts: hasThoughts) == opens)
    }

    @Test("the steps run hello, voice, microphone, call tälli, recovery key, then a few more things")
    func stepOrder() async throws {
        let (model, _, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        var seen = [model.step]
        for _ in 0..<5 {
            model.next()
            seen.append(model.step)
        }
        #expect(seen == [.hello, .voice, .microphone, .callTalli, .recoveryKey, .extras])
        #expect(model.progress == OnboardingProgress(index: 4, count: 5))
    }

    @Test("hello shows no progress; the marks count the steps after it")
    func progress() async throws {
        let (model, _, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        #expect(model.progress == nil)
        model.next()
        #expect(model.progress == OnboardingProgress(index: 0, count: 5))
    }

    @Test("a step that has nothing to ask is left out: no key waiting, the microphone already allowed")
    func leavesOutWhatIsDone() async throws {
        let services = FakeServices()
        services.microphone = .allowed
        let (model, _, _, temp) = try await makeModel(services: services, recoveryKey: nil)
        defer { withExtendedLifetime(temp) {} }
        #expect(model.steps == [.hello, .voice, .callTalli, .extras])
        #expect(model.recoveryKey == nil)
    }

    @Test("the voice step is left out when every model comes with macOS")
    func noVoiceStepWithoutDownloads() async throws {
        let services = FakeServices()
        services.setup.downloads = []
        let (model, _, _, temp) = try await makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        #expect(!model.steps.contains(.voice))
    }

    @Test("the voice step is left out when everything it would ask for is already on this Mac")
    func noVoiceStepWhenAllHere() async throws {
        let services = FakeServices()
        services.setup.downloads[0].isInstalled = true
        let (model, _, _, temp) = try await makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        #expect(!model.steps.contains(.voice))
    }

    @Test("the voice step lists each model with its size and whether it is on this Mac")
    func voiceModels() async throws {
        let (model, _, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        #expect(model.voiceModels.map(\.isInstalled) == [false, true])
        #expect(model.missingBytes == 632_000_000)
        #expect(!model.canHearYet, "without speech recognition, spoken thoughts wait for their text")
    }

    @Test(
        "what comes with macOS is named in plain words, from the roles config gives it",
        arguments: [
            (
                [ModelRole.liveTranscription, .summary, .entities],
                "built into macOS: the live preview, summaries, people, places and topics."
            ),
            ([ModelRole.summary], "built into macOS: summaries."),
            ([ModelRole.mood], nil),
            ([], nil),
        ] as [([ModelRole], String?)])
    func builtInLine(roles: [ModelRole], line: String?) {
        #expect(OnboardingModel.builtInLine(for: roles) == line)
    }

    @Test("allowing the microphone moves on to calling tälli")
    func allowsMicrophone() async throws {
        let (model, _, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .microphone)
        await model.allowMicrophone()
        #expect(model.microphone == .allowed)
        #expect(model.step == .callTalli)
    }

    @Test("refusing the microphone stays on the step")
    func refusingStays() async throws {
        let services = FakeServices()
        services.grantsMicrophone = false
        let (model, _, _, temp) = try await makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .microphone)
        await model.allowMicrophone()
        #expect(model.microphone == .denied)
        #expect(model.step == .microphone)
    }

    @Test("after a refusal, the step opens System Settings at the microphone")
    func deniedOpensSettings() async throws {
        let services = FakeServices()
        services.microphone = .denied
        let (model, _, _, temp) = try await makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        model.openMicrophoneSettings()
        #expect(services.openedMicrophoneSettings)
    }

    @Test("allowing the microphone later in System Settings is noticed when you come back")
    func noticesMicrophoneLater() async throws {
        let services = FakeServices()
        services.microphone = .denied
        let (model, _, _, temp) = try await makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .microphone)
        #expect(model.microphone == .denied)
        services.microphone = .allowed
        await model.refresh()
        #expect(model.microphone == .allowed)
        #expect(model.step == .callTalli)
    }

    @Test("an import runs once at a time")
    func oneImportAtATime() async throws {
        let (model, _, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        #expect(!model.isImporting)
        await model.importChats(from: [URL(fileURLWithPath: "/tmp/chat")])
        #expect(!model.isImporting)
        #expect(model.importMessage == "2 thoughts imported.")
    }

    @Test("a thought saved while tälli is called becomes your first thought; one saved before doesn't count")
    func firstThought() async throws {
        let (model, _, capture, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        capture.typedText = "Ein Gedanke von vorher."
        await capture.submitTyped()
        advance(model, to: .callTalli)
        #expect(model.firstThoughtID == nil)

        capture.typedText = "Okay, äh, erster Gedanke: morgens mehr laufen, before work."
        await capture.submitTyped()
        #expect(model.firstThoughtID == capture.lastSavedEntryID)
        for _ in 0..<100 where model.firstThought == nil { await Task.yield() }
        #expect(model.firstThought?.text == "Okay, äh, erster Gedanke: morgens mehr laufen, before work.")
        #expect(model.step == .callTalli, "you read it first, then go on")
    }

    @Test("the first press of the shortcut shows right away: tälli is listening, until the thought is saved")
    func listeningShows() async throws {
        let (model, _, capture, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .callTalli)
        #expect(!model.isListening)
        await capture.toggle()
        #expect(model.isListening)
        await capture.toggle()
        #expect(!model.isListening)
        #expect(model.firstThoughtID != nil)
    }

    @Test("pressing the shortcut on another step doesn't count as listening here")
    func listeningOnlyWhenCalled() async throws {
        let (model, _, capture, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .microphone)
        await capture.toggle()
        #expect(!model.isListening)
        await capture.cancel()
    }

    @Test("your first thought shows its text as soon as it is transcribed, without a refresh")
    func firstThoughtUpdates() async throws {
        let journal = FakeJournal()
        let (model, _, capture, temp) = try await makeModel(journal: journal)
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .callTalli)
        await capture.toggle()
        await capture.toggle()
        let id = try #require(model.firstThoughtID)
        for _ in 0..<100 where model.firstThought == nil { await Task.yield() }
        #expect(model.firstThought?.text.isEmpty == true, "still transcribing")

        let changed = Mutex(false)
        withObservationTracking {
            _ = model.firstThought
        } onChange: {
            changed.withLock { $0 = true }
        }
        await journal.complete(id, text: "Okay, äh, ein erster Gedanke.")
        for _ in 0..<100 where model.firstThought?.text.isEmpty != false { await Task.yield() }
        #expect(changed.withLock { $0 }, "the window is told to redraw")
        #expect(model.firstThought?.text == "Okay, äh, ein erster Gedanke.")
    }

    @Test("until its text comes, your first thought shows what tälli heard, and then no longer")
    func firstThoughtPreview() async throws {
        let journal = FakeJournal()
        let chunk = AudioSamples(samples: [0, 0.1], sampleRate: 16_000)
        let (model, _, capture, temp) = try await makeModel(
            journal: journal, preview: FakeLivePreview(), liveChunks: [chunk, chunk])
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .callTalli)
        await capture.toggle()
        for _ in 0..<200 where capture.livePreviewText.isEmpty { await Task.yield() }
        await capture.toggle()
        for _ in 0..<100 where model.firstThought == nil { await Task.yield() }
        #expect(model.firstThoughtPreview == "Gehört: 2 …")

        await journal.complete(try #require(model.firstThoughtID), text: "Okay, äh, ein erster Gedanke.")
        for _ in 0..<100 where model.firstThought?.text.isEmpty != false { await Task.yield() }
        #expect(model.firstThoughtPreview == nil)
    }

    @Test("coming back to the window re-reads the models, e.g. after adding speech recognition by hand")
    func refreshesModels() async throws {
        let services = FakeServices()
        let (model, _, _, temp) = try await makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        #expect(!model.canHearYet)
        services.setup.downloads[0].isInstalled = true
        await model.refresh()
        #expect(model.canHearYet)
    }

    @Test("the recovery key step moves on only once the last group is typed right")
    func recoveryKey() async throws {
        let (model, services, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .recoveryKey)
        let key = try #require(model.recoveryKey)
        #expect(key.recoveryKey == "7KQF-M29D-XW4R-V6JB")

        key.typedGroup = "XXXX"
        await model.confirmRecoveryKey()
        #expect(model.step == .recoveryKey)
        #expect(key.message != nil)

        key.typedGroup = "V6JB"
        key.keepInKeychain = true
        await model.confirmRecoveryKey()
        #expect(model.step == .extras)
        #expect(services.keyConfirmations.last.map { [$0.0] } == ["V6JB"])
        #expect(services.keyConfirmations.last?.1 == true)
    }

    @Test("the key step says where your thoughts are stored")
    func storageLocation() async throws {
        let (model, _, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        #expect(model.storageLocation == "on this mac, in your library")
    }

    @Test("choosing another folder hands it to the app, which says when it can't use it")
    func choosesStorage() async throws {
        let services = FakeServices()
        services.storageRefusal = "that folder already holds other thoughts."
        let (model, _, _, temp) = try await makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        let folder = URL(fileURLWithPath: "/tmp/sync")
        await model.useStorage(inside: folder)
        #expect(services.storageParents == [folder])
        #expect(model.storageMessage == "that folder already holds other thoughts.")
    }

    @Test("open at login shows what macOS really did")
    func opensAtLogin() async throws {
        let services = FakeServices()
        services.loginItemWorks = false
        let (model, _, _, temp) = try await makeModel(services: services)
        defer { withExtendedLifetime(temp) {} }
        await model.setOpensAtLogin(true)
        #expect(!model.opensAtLogin)
    }

    @Test("contacts for spellings can be switched on here")
    func usesContacts() async throws {
        let (model, _, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        await model.setUsesContacts(true)
        #expect(model.usesContacts)
    }

    @Test("an import says what came in; with nothing picked there is nothing to say")
    func imports() async throws {
        let (model, _, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        await model.importNotes(from: [])
        #expect(model.importMessage == nil)
        await model.importNotes(from: [URL(fileURLWithPath: "/tmp/notizen")])
        #expect(model.importMessage == "2 thoughts imported.")
    }

    @Test("open tällmi finishes the onboarding once")
    func finish() async throws {
        let (model, services, _, temp) = try await makeModel()
        defer { withExtendedLifetime(temp) {} }
        advance(model, to: .extras)
        await model.finish()
        await model.finish()
        #expect(model.isFinished)
        #expect(services.finishCount == 1)
    }

    @Test("the shortcut can be changed right here; the keys show the new one, and it calls tälli at once")
    func changesShortcut() async throws {
        let temp = try TemporaryDirectory()
        let capture = CaptureViewModel(recorder: FakeRecorder(folder: temp.url), journal: FakeJournal())
        let store = HotkeySettingsViewModelTests.FakeStore("control+option+t")
        var applied: [String] = []
        let shortcut = HotkeySettingsViewModel(
            store: store, checker: HotkeySettingsViewModelTests.FakeChecker(taken: [])
        ) {
            applied.append($0.settingValue)
        }
        let model = OnboardingModel(
            services: FakeServices(), capture: capture, shortcut: shortcut, finishKey: "↩", recoveryKey: nil)
        await model.load()
        #expect(model.keycaps == ["⌃", "⌥", "T"])

        await model.shortcut.record(Hotkey(key: .letter("k"), modifiers: [.control, .option]))
        #expect(model.keycaps == ["⌃", "⌥", "K"])
        #expect(await store.saved == "control+option+k")
        #expect(applied == ["control+option+k"])
        withExtendedLifetime(temp) {}
    }

    @Test("⌘K show onboarding asks the app to open it again")
    func replayFromPalette() async {
        let explore = ExploreViewModel(library: FakeLibrary(entries: []), autosaveDelay: .zero)
        var asked = 0
        explore.onShowOnboarding = { asked += 1 }
        await explore.perform(.showOnboarding)
        #expect(asked == 1)
    }

    @Test(
        "the shortcut is shown as one key per symbol, the key itself last",
        arguments: [("⌃⌥T", ["⌃", "⌥", "T"]), ("⌥⌘ space", ["⌥", "⌘", "space"]), ("F5", ["F5"])])
    func keycaps(label: String, keys: [String]) {
        #expect(OnboardingModel.keycaps(for: label) == keys)
    }
}
