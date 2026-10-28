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

/// How far a model's files are on their way to this Mac.
public enum VoiceModelState: Sendable, Equatable {
    case missing
    /// Next in line while another one downloads.
    case waiting
    case downloading(received: Int64)
    case installed
    /// The last download stopped before every file arrived and matched.
    case failed
}

/// A model tällmi needs files for, and whether they are on this Mac.
public struct VoiceModelStatus: Sendable, Equatable, Identifiable {
    public var role: ModelRole
    public var name: String
    public var bytes: Int64
    public var state: VoiceModelState
    public var id: String { role.rawValue }

    public var isInstalled: Bool {
        get { state == .installed }
        set { state = newValue ? .installed : .missing }
    }

    public init(role: ModelRole, name: String, bytes: Int64, state: VoiceModelState) {
        self.role = role
        self.name = name
        self.bytes = bytes
        self.state = state
    }

    public init(role: ModelRole, name: String, bytes: Int64, isInstalled: Bool) {
        self.init(role: role, name: name, bytes: bytes, state: isInstalled ? .installed : .missing)
    }
}

/// What the voice step knows: the models to download, and the roles that run on what macOS brings.
public struct VoiceSetup: Sendable, Equatable {
    public var downloads: [VoiceModelStatus]
    public var builtIn: [ModelRole]

    public init(downloads: [VoiceModelStatus], builtIn: [ModelRole]) {
        self.downloads = downloads
        self.builtIn = builtIn
    }
}

/// How big tälli is in the onboarding window and how much of it peeks in (from config).
public struct OnboardingTalliSizes: Sendable, Equatable {
    public var hello: Double
    public var corner: Double
    /// The part of tälli above the window's bottom edge, 0…1.
    public var peek: Double

    public init(hello: Double, corner: Double, peek: Double) {
        self.hello = hello
        self.corner = corner
        self.peek = peek
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
    func voiceSetup() async -> VoiceSetup
    /// Starts downloading what is missing, or follows the download already running: the voice setup each time
    /// it changes, until the download ends. The download goes on when nobody follows it.
    func downloadVoiceModels() -> AsyncStream<VoiceSetup>
    func microphoneAccess() async -> MicrophoneAccess
    /// Asks macOS; true when allowed.
    func requestMicrophone() async -> Bool
    func openMicrophoneSettings()
    func showModelsFolder()
    func confirmRecoveryKey(lastGroup: String, keepInKeychain: Bool) async throws -> Bool
    /// Where the thoughts are stored, in plain words.
    func storageLocation() async -> String
    /// Stores the thoughts in a "tällmi" folder inside `parent`, or opens the thoughts already there; tällmi
    /// restarts for it. Returns what to tell you.
    func useStorage(inside parent: URL) async -> String?
    func opensAtLogin() async -> Bool
    /// Returns what macOS really did.
    func setOpensAtLogin(_ on: Bool) async -> Bool
    func usesContacts() async -> Bool
    /// Returns what is really on, after macOS asked about contacts.
    func setUsesContacts(_ on: Bool) async -> Bool
    /// Imports the files you picked and says what happened; nil when there was nothing to import.
    func importNotes(from urls: [URL]) async -> String?
    func importChats(from urls: [URL]) async -> String?
    /// Remembers that the onboarding is done; the window then closes and the tällmi window opens.
    func finish() async
}

/// The first launch: hello, the voice models, the microphone, a first thought, the recovery key, a few extras.
/// Steps with nothing to ask are left out.
@Observable
public final class OnboardingModel {
    public private(set) var step: OnboardingStep = .hello
    public private(set) var steps: [OnboardingStep] = [.hello]
    public private(set) var voiceModels: [VoiceModelStatus] = []
    public private(set) var builtInRoles: [ModelRole] = []
    public private(set) var storageLocation = ""
    public private(set) var storageMessage: String?
    public private(set) var microphone: MicrophoneAccess = .notAsked
    public private(set) var opensAtLogin = false
    public private(set) var usesContacts = false
    public private(set) var importMessage: String?
    public private(set) var isImporting = false
    public private(set) var isFinished = false
    @ObservationIgnored private var isFollowingDownload = false
    /// The new Recovery Key to save and confirm, if the Archive was just created.
    public let recoveryKey: RecoveryKeyViewModel?
    /// The shortcut that calls tälli; changing it here saves it and calls tälli with it at once.
    public let shortcut: HotkeySettingsViewModel
    /// The key that saves what you said (`companion.finish_key`), as macOS shows it.
    public let finishKey: String
    // The Entry saved last before tälli was called here, so only a new one counts as your first thought.
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

    /// "built into macOS: the live preview, summaries." for the roles config runs on what macOS brings.
    public nonisolated static func builtInLine(for roles: [ModelRole]) -> String? {
        let words = roles.compactMap { role -> String? in
            switch role {
            case .liveTranscription: "the live preview"
            case .summary: "summaries"
            case .entities: "people, places and topics"
            default: nil
            }
        }
        return words.isEmpty ? nil : "built into macOS: " + words.joined(separator: ", ") + "."
    }

    public func load() async {
        await shortcut.load()
        await loadVoice()
        storageLocation = await services.storageLocation()
        microphone = await services.microphoneAccess()
        opensAtLogin = await services.opensAtLogin()
        usesContacts = await services.usesContacts()
        var steps: [OnboardingStep] = [.hello]
        if missingBytes > 0 { steps.append(.voice) }
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

    /// tälli is listening for your first thought: the first press of the shortcut, before the thought is saved.
    public var isListening: Bool {
        step == .callTalli && firstThoughtID == nil && capture.isRecording
    }

    /// How loud you are while tälli listens, 0…1, for tälli in the window.
    public var listeningLevel: Float { capture.level }

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
        await loadVoice()
        await refreshMicrophone()
    }

    private func loadVoice() async {
        let setup = await services.voiceSetup()
        voiceModels = setup.downloads
        builtInRoles = setup.builtIn
    }

    /// A model is downloading or waiting its turn.
    public var isDownloading: Bool {
        voiceModels.contains {
            switch $0.state {
            case .waiting, .downloading: true
            case .missing, .installed, .failed: false
            }
        }
    }

    public var downloadFailed: Bool { voiceModels.contains { $0.state == .failed } }

    /// tälli thinks ("ähmm") on the voice step while the download runs.
    public var talliIsThinking: Bool { step == .voice && isDownloading }

    /// Downloads what is missing and follows it until it ends, also after you went on to the next steps.
    /// Pressing again while it runs changes nothing.
    public func download() async {
        guard !isFollowingDownload else { return }
        isFollowingDownload = true
        defer { isFollowingDownload = false }
        for await setup in services.downloadVoiceModels() {
            voiceModels = setup.downloads
            builtInRoles = setup.builtIn
        }
    }

    /// "632 MB", "1.3 GB": megabytes whole, gigabytes to one decimal, as the design shows them.
    public nonisolated static func size(_ bytes: Int64, locale: Locale = .current) -> String {
        let measurement = Measurement(value: Double(bytes), unit: UnitInformationStorage.bytes)
        let gigabytes = measurement.converted(to: .gigabytes)
        let (value, digits) = gigabytes.value >= 1 ? (gigabytes, 1) : (measurement.converted(to: .megabytes), 0)
        return value.formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(digits))
            )
            .locale(locale))
    }

    public nonisolated static func downloadTitle(missing: Int64, locale: Locale = .current) -> String {
        "download " + size(missing, locale: locale)
    }

    /// What a row says on the right: its size, how far it is, or that it is here.
    public nonisolated static func sizeLine(for status: VoiceModelStatus, locale: Locale = .current) -> String {
        switch status.state {
        case .missing: size(status.bytes, locale: locale)
        case .waiting: "next · " + size(status.bytes, locale: locale)
        case .downloading(let received):
            Measurement(value: Double(received), unit: UnitInformationStorage.bytes).converted(to: .megabytes)
                .value.formatted(.number.precision(.fractionLength(0)).locale(locale))
                + " of " + size(status.bytes, locale: locale)
        case .installed: "on this mac"
        case .failed: "didn't finish"
        }
    }

    public func useStorage(inside parent: URL) async {
        storageMessage = await services.useStorage(inside: parent)
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
