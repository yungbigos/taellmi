import Audio
import Config
import CryptoKit
import Domain
import Features
import FluidAudioEngine
import Foundation
import IOKit.ps
import MLXEmbedderEngine
import Persistence
import Pipeline
import Search
import SpeechAnalyzerEngine
import Synchronization
import SystemServices
import os

/// The composition root: the only place that knows every concrete implementation.
public final class AppEnvironment {
    /// Engines this build can run, by the engine key used in `model` config rows.
    public static let liveEngines: [String: TranscriberFactory] = [
        ParakeetTranscriber.engineKey: ParakeetTranscriber.factory
    ]
    /// Embedding engines, by engine key.
    public static let liveEmbedders: [String: EmbedderFactory] = [MLXEmbedder.engineKey: MLXEmbedder.factory]
    /// Live-preview engines, by engine key.
    public static let livePreviewEngines: [String: LivePreviewFactory] = [
        AppleSpeechLivePreview.engineKey: AppleSpeechLivePreview.factory
    ]

    public let journal: any Journal
    public let captureModel: CaptureViewModel
    public let vocabularyModel: VocabularyViewModel
    public let appearanceModel: AppearanceViewModel
    public let hotkeyStore: any HotkeyStore
    public let exploreHotkeyStore: any HotkeyStore
    public let exploreModel: ExploreViewModel
    public let settings: SettingsStore
    /// The configured global hotkey; read once at start.
    public private(set) var hotkey: Hotkey?

    private let paths: AppPaths
    /// Where the Archive is (Library by default, or the folder you chose).
    public let archiveRoot: URL
    /// Set after a fresh setup until you confirm you saved it (ADR 0010).
    /// Thoughts the last start couldn't encrypt; they stay out of the index and in the backup.
    public private(set) var migrationFailures: Int?

    public private(set) var pendingRecoveryKey: RecoveryKey? {
        didSet { pendingBox.value.withLock { $0 = pendingRecoveryKey?.formatted } }
    }
    private let pendingBox = PendingRecoveryKeyBox()
    let vault: ArchiveVault?
    private let storage: any ArchiveStorage
    private let archiveKey: SymmetricKey?
    let database: AppDatabase
    private let files: EntryFileStore
    private let index: EntryIndex
    private let runner: PipelineRunner
    private let engines: EngineCache<ContinuousClock>
    private let pipelineKick: PipelineKick
    private let logger = Logger(subsystem: "app.taellmi", category: "app")
    private var maintenanceTask: Task<Void, Never>?
    private var memoryPressure: (any DispatchSourceMemoryPressure)?

    /// Builds the real app: opens the database, finds the Archive, and opens its key (ADR 0010).
    /// Throws `ArchiveLockedError` when this Mac needs the Recovery Key first.
    public static func live() async throws -> AppEnvironment {
        let (paths, database, sampleRate, root) = try await Task.detached(priority: .userInitiated) {
            let paths = try AppPaths.live()
            let database = try AppDatabase.open(at: paths.database)
            _ = try Seeder(database: database).apply(SeedBundle.bundled())
            let settings = SettingsStore(database: database)
            let editor = ConfigEditor(database: database)
            // A move you scheduled runs now, before anything reads or writes the Archive.
            try? ArchiveLocation.applyPendingMove(settings: settings, editor: editor, default: paths.archive)
            return (
                paths, database, try settings.number(SettingKeys.sampleRate),
                try ArchiveLocation.resolve(settings: settings, editor: editor, default: paths.archive)
            )
        }.value
        let vault = ArchiveVault(root: root, keyStore: KeychainKeyStore())
        guard case .unlocked(let key, let newRecoveryKey) = try vault.open() else {
            throw ArchiveLockedError(vault: vault)
        }
        let storage = EncryptedStorage(root: root, key: key, decryptedCache: paths.decryptedCache)
        let environment = try AppEnvironment(
            paths: paths, archiveRoot: root, storage: storage, archiveKey: key, vault: vault, database: database,
            engines: liveEngines, embedders: liveEmbedders, livePreviews: livePreviewEngines,
            recorder: MicrophoneRecorder(scratchFolder: paths.scratch, sampleRate: sampleRate))
        environment.pendingRecoveryKey = newRecoveryKey
        return environment
    }

    /// You confirmed the new Recovery Key by typing its last group.
    public func confirmRecoveryKey(lastGroup: String, keepInKeychain: Bool) throws -> Bool {
        guard let vault, try vault.confirmRecoveryKey(lastGroup: lastGroup, keepInKeychain: keepInKeychain) else {
            return false
        }
        pendingRecoveryKey = nil
        return true
    }

    public convenience init(
        paths: AppPaths, engines: [String: TranscriberFactory], embedders: [String: EmbedderFactory] = [:],
        livePreviews: [String: LivePreviewFactory] = [:], recorder: any AudioRecording
    ) throws {
        try self.init(
            paths: paths, archiveRoot: paths.archive, storage: PlainFolderStorage(root: paths.archive), archiveKey: nil,
            vault: nil,
            database: AppDatabase.open(at: paths.database), engines: engines, embedders: embedders,
            livePreviews: livePreviews, recorder: recorder)
    }

    init(
        paths: AppPaths, archiveRoot: URL, storage: any ArchiveStorage, archiveKey: SymmetricKey?, vault: ArchiveVault?,
        database: AppDatabase,
        engines factories: [String: TranscriberFactory], embedders: [String: EmbedderFactory],
        livePreviews: [String: LivePreviewFactory],
        recorder: any AudioRecording
    ) throws {
        self.paths = paths
        self.archiveRoot = archiveRoot
        self.storage = storage
        self.archiveKey = archiveKey
        self.vault = vault
        self.database = database
        settings = SettingsStore(database: database)
        files = EntryFileStore(storage: storage)
        index = EntryIndex(database: database)
        let installation = ModelInstallation(root: paths.models)
        let settings = settings
        let vocabularySources: [any VocabularySource] = [
            CurationStore(storage: storage),
            SettingGatedSource(
                settings: settings, key: SettingKeys.vocabularyUseContacts, source: ContactsVocabularySource()),
        ]
        engines = EngineCache(
            factories: factories, embedders: embedders, installation: installation, clock: ContinuousClock(),
            // If the setting cannot be read, unload right away: the resource-safe choice.
            idleUnload: { (try? settings.number(SettingKeys.idleUnloadSeconds)).map { .seconds($0) } ?? .zero })
        let resolver = ModelResolver(
            database: database, registeredEngines: engines.registeredEngines.union(livePreviews.keys),
            installation: installation,
            conditions: { RuntimeConditions(onBattery: PowerSource.isOnBattery) })
        runner = PipelineRunner(
            jobs: JobQueue(database: database), files: files, index: index,
            fragments: FragmentStore(database: database), vectors: VectorStore(database: database),
            resolver: resolver, engines: engines, embedders: engines,
            settings: settings, pipeline: PipelineConfig(database: database),
            vocabulary: [
                CurationStore(storage: storage),
                SettingGatedSource(
                    settings: settings, key: SettingKeys.vocabularyUseContacts, source: ContactsVocabularySource()),
            ],
            classifier: NaturalLanguageClassifier())
        let kick = PipelineKick(runner: runner)
        pipelineKick = kick
        journal = LiveJournal(
            files: files, index: index, runner: runner, archiveFolder: archiveRoot,
            kickPipeline: { kick.kick() })
        captureModel = CaptureViewModel(
            recorder: recorder, journal: journal,
            preview: LivePreviewService(resolver: resolver, factories: livePreviews, vocabulary: vocabularySources),
            minimumDuration: (try? settings.number(SettingKeys.minimumRecordingSeconds)) ?? 0)
        appearanceModel = AppearanceViewModel(
            store: LiveAppearanceStore(settings: settings, editor: ConfigEditor(database: database)))
        hotkeyStore = LiveHotkeyStore(
            settings: settings, editor: ConfigEditor(database: database), key: SettingKeys.hotkey)
        exploreHotkeyStore = LiveHotkeyStore(
            settings: settings, editor: ConfigEditor(database: database), key: SettingKeys.exploreHotkey)
        exploreModel = ExploreViewModel(
            library: LiveExploreLibrary(
                files: files, index: index,
                search: HybridSearch(
                    index: index, fragments: FragmentStore(database: database),
                    vectors: VectorStore(database: database), resolver: resolver, embedders: engines,
                    settings: settings),
                onChange: { kick.kick() }),
            autosaveDelay: .seconds((try? settings.number(SettingKeys.exploreAutosaveDelaySeconds)) ?? 0),
            startView: (try? settings.string(SettingKeys.exploreStartView)).flatMap(ExploreViewKind.init) ?? .stack,
            capture: captureModel)
        vocabularyModel = VocabularyViewModel(
            settings: LiveVocabularySettings(
                curation: CurationStore(storage: storage), settings: settings,
                editor: ConfigEditor(database: database)))
    }

    /// Brings config and index up to date and resumes unfinished work, all off the main actor.
    public func start() async throws {
        let work = StartupWork(
            paths: paths, database: database, files: files, index: index, runner: runner, storage: storage,
            archiveRoot: archiveRoot, archiveKey: archiveKey)
        migrationFailures = try await Task.detached(priority: .utility) { try await work.run() }.value
        hotkey = (try? settings.string(SettingKeys.hotkey)).flatMap { try? Hotkey(parsing: $0) }
        await appearanceModel.load()
        exploreModel.shortcuts = commandShortcuts()
        captureModel.startObservingEntries()
        pipelineKick.kick()
        try startMaintenance()
        watchMemoryPressure()
    }

    /// The privacy tab.
    public func makePrivacyModel(restart: @escaping () -> Void) -> PrivacyViewModel {
        let pending = pendingBox
        return PrivacyViewModel(
            settings: LivePrivacySettings(
                archiveRoot: archiveRoot, files: files, settings: settings, editor: ConfigEditor(database: database),
                pending: { pending.value.withLock { $0 } }),
            restart: restart)
    }

    /// Every command's shortcut, freshly read from config.
    public func commandShortcuts() -> [Command: Hotkey] {
        CommandShortcuts.load(from: settings)
    }

    /// A store for one command's shortcut setting.
    public func commandShortcutStore(_ command: Command) -> any HotkeyStore {
        LiveHotkeyStore(settings: settings, editor: ConfigEditor(database: database), key: command.settingKey)
    }

    /// The configured shortcut for the Explore window.
    public var exploreHotkey: Hotkey? {
        (try? settings.string(SettingKeys.exploreHotkey)).flatMap { try? Hotkey(parsing: $0) }
    }

    /// tälli's settings from config.
    public func companionSettings() -> CompanionSettings {
        CompanionSettings(
            cursorOffset: (try? settings.number(SettingKeys.companionCursorOffset)) ?? 0,
            savedDisplaySeconds: (try? settings.number(SettingKeys.companionSavedDisplaySeconds)) ?? 0,
            followsCursor: (try? settings.bool(SettingKeys.companionFollowsCursor)) ?? false,
            followSmoothing: (try? settings.number(SettingKeys.companionFollowSmoothing)) ?? 1,
            finishKey: (try? settings.string(SettingKeys.companionFinishKey)).flatMap { try? Hotkey(parsingKey: $0) }
                ?? .enter,
            cancelKey: (try? settings.string(SettingKeys.companionCancelKey)).flatMap { try? Hotkey(parsingKey: $0) }
                ?? .escape)
    }

    /// Waits until the pipeline has nothing left to do. Used by tests.
    func waitForPipeline() async {
        await pipelineKick.waitUntilIdle()
    }

    /// Periodically unloads idle models and retries jobs that were waiting (e.g. for a model download).
    private func startMaintenance() throws {
        let interval = try settings.number(SettingKeys.maintenanceIntervalSeconds)
        maintenanceTask?.cancel()
        let engines = engines
        let kick = pipelineKick
        maintenanceTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                await engines.evictIdle()
                kick.kick()
            }
        }
    }

    private func watchMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        let engines = engines
        source.setEventHandler { Task { await engines.unloadIfIdle() } }
        source.activate()
        memoryPressure = source
    }

    deinit {
        maintenanceTask?.cancel()
        memoryPressure?.cancel()
    }
}

/// Runs the pipeline in the background whenever there may be new work.
nonisolated final class PipelineKick: Sendable {
    private let runner: PipelineRunner
    private let current = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(runner: PipelineRunner) {
        self.runner = runner
    }

    func kick() {
        let runner = runner
        current.withLock { task in
            let previous = task
            task = Task.detached(priority: .utility) {
                await previous?.value
                await runner.runPending()
            }
        }
    }

    func waitUntilIdle() async {
        await current.withLock { $0 }?.value
    }
}

/// The not-yet-confirmed Recovery Key, readable from the privacy settings off the main actor.
nonisolated final class PendingRecoveryKeyBox: Sendable {
    let value = Mutex<String?>(nil)
}

/// A Vocabulary source that only contributes while a bool setting is on (e.g. the contacts opt-in).
nonisolated struct SettingGatedSource: VocabularySource {
    let settings: SettingsStore
    let key: String
    let source: any VocabularySource

    func terms() async throws -> [VocabularyTerm] {
        guard try settings.bool(key) else { return [] }
        return try await source.terms()
    }
}

nonisolated enum PowerSource {
    static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }
}
