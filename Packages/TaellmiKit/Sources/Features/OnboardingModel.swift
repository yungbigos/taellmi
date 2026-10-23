import Domain
import Foundation
import Observation

/// One step of the first-launch onboarding (docs/brand.md voice; design on the onboarding canvas).
public enum OnboardingStep: Sendable, Equatable {
    case hello
    case voice
    case microphone
    case callTalli
    case recoveryKey
    case extras
}

/// Whether macOS lets tällmi use the microphone.
public enum MicrophoneAccess: Sendable, Equatable {
    case notAsked
    case allowed
    case denied
}

/// A model tällmi needs files for, and whether they are on this Mac.
public struct VoiceModelStatus: Sendable, Equatable, Identifiable {
    public var role: ModelRole
    public var name: String
    public var bytes: Int64
    public var isInstalled: Bool
    public var id: String { role.rawValue }

    public init(role: ModelRole, name: String, bytes: Int64, isInstalled: Bool) {
        self.role = role
        self.name = name
        self.bytes = bytes
        self.isInstalled = isInstalled
    }
}

/// Where the progress marks are: the steps after hello, counted from 0.
public struct OnboardingProgress: Sendable, Equatable {
    public var index: Int
    public var count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }
}

/// What the onboarding needs from the app and from macOS.
public protocol OnboardingServices: AnyObject {
    func voiceModels() async -> [VoiceModelStatus]
    func microphoneAccess() async -> MicrophoneAccess
    /// Asks macOS; true when allowed.
    func requestMicrophone() async -> Bool
    func openMicrophoneSettings()
    func showModelsFolder()
    func confirmRecoveryKey(lastGroup: String, keepInKeychain: Bool) async throws -> Bool
    func opensAtLogin() async -> Bool
    /// Returns what macOS really did.
    func setOpensAtLogin(_ on: Bool) async -> Bool
    func usesContacts() async -> Bool
    /// Returns what is really on, after macOS asked about contacts.
    func setUsesContacts(_ on: Bool) async -> Bool
    /// Imports the files you picked and says what happened; nil when there was nothing to import.
    func importNotes(from urls: [URL]) async -> String?
    func importChats(from urls: [URL]) async -> String?
    /// Remembers that the onboarding is done and opens tällmi.
    func finish() async
}

/// The first launch: hello, the voice models, the microphone, a first thought, the recovery key, a few extras.
/// Steps with nothing to ask are left out.
@Observable
public final class OnboardingModel {
    public private(set) var step: OnboardingStep = .hello
    public private(set) var steps: [OnboardingStep] = [.hello]
    public private(set) var voiceModels: [VoiceModelStatus] = []
    public private(set) var microphone: MicrophoneAccess = .notAsked
    public private(set) var opensAtLogin = false
    public private(set) var usesContacts = false
    public private(set) var importMessage: String?
    public private(set) var isImporting = false
    public private(set) var isFinished = false
    /// The new Recovery Key to save and confirm, if the Archive was just created.
    public let recoveryKey: RecoveryKeyViewModel?
    /// The shortcut that calls tälli; changing it here saves it and calls tälli with it at once.
    public let shortcut: HotkeySettingsViewModel
    /// The key that saves what you said (`companion.finish_key`), as macOS shows it.
    public let finishKey: String
    /// The Entry saved last before tälli was called here, so only a new one counts as your first thought.
    private var savedBeforeCall: String?

    @ObservationIgnored private let services: any OnboardingServices
    @ObservationIgnored private let capture: CaptureViewModel

    public init(
        services: any OnboardingServices, capture: CaptureViewModel, shortcut: HotkeySettingsViewModel,
        finishKey: String, recoveryKey: String?
    ) {
        self.services = services
        self.capture = capture
        self.shortcut = shortcut
        self.finishKey = finishKey
        self.recoveryKey = recoveryKey.map { key in
            RecoveryKeyViewModel(recoveryKey: key) { group, keep in
                try await services.confirmRecoveryKey(lastGroup: group, keepInKeychain: keep)
            }
        }
    }

    /// Only a fresh tällmi opens the onboarding: one without thoughts that hasn't finished it.
    public nonisolated static func shouldOpen(completed: Bool, hasThoughts: Bool) -> Bool {
        !completed && !hasThoughts
    }

    /// "⌃⌥T" → ["⌃", "⌥", "T"]: each modifier is a key, the rest is the last one.
    public nonisolated static func keycaps(for label: String) -> [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let symbols = label.prefix { modifiers.contains($0) }.map(String.init)
        let key = label.dropFirst(symbols.count).trimmingCharacters(in: .whitespaces)
        return symbols + (key.isEmpty ? [] : [key])
    }

    /// The shortcut that calls tälli, one key per cap.
    public var keycaps: [String] { Self.keycaps(for: shortcut.label) }

    public func load() async {
        await shortcut.load()
        voiceModels = await services.voiceModels()
        microphone = await services.microphoneAccess()
        opensAtLogin = await services.opensAtLogin()
        usesContacts = await services.usesContacts()
        var steps: [OnboardingStep] = [.hello]
        if !voiceModels.isEmpty { steps.append(.voice) }
        if microphone != .allowed { steps.append(.microphone) }
        steps.append(.callTalli)
        if recoveryKey != nil { steps.append(.recoveryKey) }
        steps.append(.extras)
        self.steps = steps
    }

    /// The progress marks, or nil on hello.
    public var progress: OnboardingProgress? {
        guard step != .hello, let index = steps.firstIndex(of: step) else { return nil }
        return OnboardingProgress(index: index - 1, count: steps.count - 1)
    }

    /// The bytes still to download.
    public var missingBytes: Int64 {
        voiceModels.filter { !$0.isInstalled }.reduce(0) { $0 + $1.bytes }
    }

    /// Whether spoken thoughts get their text now; without the speech model they wait for it.
    public var canHearYet: Bool {
        voiceModels.first { $0.role == .transcription }?.isInstalled ?? true
    }

    /// The thought you saved since tälli was called here.
    public var firstThoughtID: String? {
        guard step == .callTalli, let id = capture.lastSavedEntryID, id != savedBeforeCall else { return nil }
        return id
    }

    public var firstThought: Entry? {
        guard let id = firstThoughtID else { return nil }
        return capture.recentEntries.first { $0.id == id }
    }

    /// What tälli heard for your first thought, while its real text is still on the way.
    public var firstThoughtPreview: String? {
        guard firstThoughtID != nil, firstThought?.text.isEmpty != false, !capture.lastSavedPreview.isEmpty else {
            return nil
        }
        return capture.lastSavedPreview
    }

    public func next() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        step = steps[index + 1]
        if step == .callTalli { savedBeforeCall = capture.lastSavedEntryID }
    }

    public func allowMicrophone() async {
        microphone = await services.requestMicrophone() ? .allowed : .denied
        if microphone == .allowed, step == .microphone { next() }
    }

    /// Back in the window: the microphone may be allowed now, or a model added by hand.
    public func refresh() async {
        voiceModels = await services.voiceModels()
        await refreshMicrophone()
    }

    private func refreshMicrophone() async {
        let access = await services.microphoneAccess()
        guard access != .notAsked else { return }
        microphone = access
        if access == .allowed, step == .microphone { next() }
    }

    public func openMicrophoneSettings() {
        services.openMicrophoneSettings()
    }

    public func showModelsFolder() {
        services.showModelsFolder()
    }

    public func confirmRecoveryKey() async {
        guard let recoveryKey else { return }
        await recoveryKey.confirm()
        if recoveryKey.isDone, step == .recoveryKey { next() }
    }

    public func setOpensAtLogin(_ on: Bool) async {
        opensAtLogin = await services.setOpensAtLogin(on)
    }

    public func setUsesContacts(_ on: Bool) async {
        usesContacts = await services.setUsesContacts(on)
    }

    public func importNotes(from urls: [URL]) async {
        await importing { await services.importNotes(from: urls) }
    }

    public func importChats(from urls: [URL]) async {
        await importing { await services.importChats(from: urls) }
    }

    private func importing(_ run: () async -> String?) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        if let message = await run() { importMessage = message }
    }

    public func finish() async {
        guard !isFinished else { return }
        isFinished = true
        await services.finish()
    }
}
