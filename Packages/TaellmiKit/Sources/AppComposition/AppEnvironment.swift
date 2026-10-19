import Audio
import Config
import Domain
import Features
import FluidAudioEngine
import Foundation
import IOKit.ps
import Persistence
import Pipeline
import SpeechAnalyzerEngine
import SystemServices
import os

/// The composition root: the only place that knows every concrete implementation.
public final class AppEnvironment {
    /// Engines this build can run, by the engine key used in `model` config rows.
    public static let liveEngines: [String: TranscriberFactory] = [
        ParakeetTranscriber.engineKey: ParakeetTranscriber.factory
    ]
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
    let database: AppDatabase
    private let files: EntryFileStore
    private let index: EntryIndex
    private let runner: PipelineRunner
    private let engines: EngineCache<ContinuousClock>
    private let pipelineKick: PipelineKick
    private let logger = Logger(subsystem: "app.taellmi", category: "app")
    private var maintenanceTask: Task<Void, Never>?
    private var memoryPressure: (any DispatchSourceMemoryPressure)?

    /// Builds the real app. Opening and migrating the database happens off the main actor.
    public static func live() async throws -> AppEnvironment {
        let (paths, database, sampleRate) = try await Task.detached(priority: .userInitiated) {
            let paths = try AppPaths.live()
            let database = try AppDatabase.open(at: paths.database)
            _ = try Seeder(database: database).apply(SeedBundle.bundled())
            return (paths, database, try SettingsStore(database: database).number(SettingKeys.sampleRate))
        }.value
        return try AppEnvironment(
            paths: paths, database: database, engines: liveEngines, livePreviews: livePreviewEngines,
            recorder: MicrophoneRecorder(scratchFolder: paths.scratch, sampleRate: sampleRate))
    }

    public convenience init(
        paths: AppPaths, engines: [String: TranscriberFactory], livePreviews: [String: LivePreviewFactory] = [:],
        recorder: any AudioRecording
    ) throws {
        try self.init(
            paths: paths, database: AppDatabase.open(at: paths.database), engines: engines,
            livePreviews: livePreviews, recorder: recorder)
    }

    init(
        paths: AppPaths, database: AppDatabase, engines factories: [String: TranscriberFactory],
        livePreviews: [String: LivePreviewFactory], recorder: any AudioRecording
    ) throws {
        self.paths = paths
        self.database = database
        settings = SettingsStore(database: database)
        files = EntryFileStore(storage: PlainFolderStorage(root: paths.archive))
        index = EntryIndex(database: database)
        let installation = ModelInstallation(root: paths.models)
        let settings = settings
        let vocabularySources: [any VocabularySource] = [
            CurationStore(storage: PlainFolderStorage(root: paths.archive)),
            SettingGatedSource(
                settings: settings, key: SettingKeys.vocabularyUseContacts, source: ContactsVocabularySource()),
        ]
        engines = EngineCache(
            factories: factories, installation: installation, clock: ContinuousClock(),
            // If the setting cannot be read, unload right away: the resource-safe choice.
            idleUnload: { (try? settings.number(SettingKeys.idleUnloadSeconds)).map { .seconds($0) } ?? .zero })
        let resolver = ModelResolver(
            database: database, registeredEngines: Set(factories.keys).union(livePreviews.keys),
            installation: installation,
            conditions: { RuntimeConditions(onBattery: PowerSource.isOnBattery) })
        runner = PipelineRunner(
            jobs: JobQueue(database: database), files: files, index: index, resolver: resolver, engines: engines,
            settings: settings, pipeline: PipelineConfig(database: database),
            vocabulary: [
                CurationStore(storage: PlainFolderStorage(root: paths.archive)),
                SettingGatedSource(
                    settings: settings, key: SettingKeys.vocabularyUseContacts, source: ContactsVocabularySource()),
            ],
            classifier: NaturalLanguageClassifier())
        let kick = PipelineKick(runner: runner)
        pipelineKick = kick
        journal = LiveJournal(
            files: files, index: index, runner: runner, archiveFolder: paths.archive,
            kickPipeline: { kick.kick() })
        captureModel = CaptureViewModel(
            recorder: recorder, journal: journal,
            preview: LivePreviewService(resolver: resolver, factories: livePreviews, vocabulary: vocabularySources))
        appearanceModel = AppearanceViewModel(
            store: LiveAppearanceStore(settings: settings, editor: ConfigEditor(database: database)))
        hotkeyStore = LiveHotkeyStore(
            settings: settings, editor: ConfigEditor(database: database), key: SettingKeys.hotkey)
        exploreHotkeyStore = LiveHotkeyStore(
            settings: settings, editor: ConfigEditor(database: database), key: SettingKeys.exploreHotkey)
        exploreModel = ExploreViewModel(
            library: LiveExploreLibrary(files: files, index: index),
            autosaveDelay: .seconds((try? settings.number(SettingKeys.exploreAutosaveDelaySeconds)) ?? 0))
        vocabularyModel = VocabularyViewModel(
            settings: LiveVocabularySettings(
                curation: CurationStore(storage: PlainFolderStorage(root: paths.archive)), settings: settings,
                editor: ConfigEditor(database: database)))
    }

    /// Brings config and index up to date and resumes unfinished work, all off the main actor.
    public func start() async throws {
        let work = StartupWork(paths: paths, database: database, files: files, index: index, runner: runner)
        try await Task.detached(priority: .utility) { try await work.run() }.value
        hotkey = (try? settings.string(SettingKeys.hotkey)).flatMap { try? Hotkey(parsing: $0) }
        await appearanceModel.load()
        captureModel.startObservingEntries()
        pipelineKick.kick()
        try startMaintenance()
        watchMemoryPressure()
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
