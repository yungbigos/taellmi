import Domain
import Foundation
import GRDB
import Persistence

/// Names of the settings the code reads. Values (and defaults) live in the database and seed files.
public enum SettingKeys {
    public static let hotkey = "capture.hotkey"
    public static let sampleRate = "capture.sample_rate"
    public static let minimumRecordingSeconds = "capture.min_recording_s"
    public static let discardSilentRecordings = "capture.discard_silent_recordings"
    public static let idleUnloadSeconds = "models.idle_unload_s"
    public static let maxJobAttempts = "pipeline.max_attempts"
    public static let segmentMaxPauseSeconds = "transcription.segment_max_pause_s"
    public static let retryBackoffSeconds = "pipeline.retry_backoff_s"
    public static let waitForModelSeconds = "pipeline.wait_for_model_s"
    public static let maintenanceIntervalSeconds = "app.maintenance_interval_s"
    public static let vocabularyMinSimilarityNames = "vocabulary.min_similarity_names"
    public static let vocabularyMinSimilarityOther = "vocabulary.min_similarity_other"
    public static let vocabularyUseContacts = "vocabulary.use_contacts"
    public static let textCase = "appearance.text_case"
    /// Thoughts shorter than this get concepts but no summary (ADR 0012).
    public static let summaryMinWords = "summary.min_words"
    /// How many leading letters of a summary word must appear in the thought for the summary to be shown.
    public static let summaryStemLength = "summary.stem_length"
    public static let archiveLocationBookmark = "archive.location_bookmark"
    public static let archivePendingMoveBookmark = "archive.pending_move_bookmark"
    public static let lockWindow = "privacy.lock_window"
    public static let exploreHotkey = "explore.hotkey"
    public static let exploreAutosaveDelaySeconds = "explore.autosave_delay_s"
    /// The view the tällmi window opens in: `stack`, `flow` or `time`.
    public static let exploreStartView = "explore.start_view"
    /// File extensions "import from apple notes" treats as notes, comma-separated.
    public static let importNoteExtensions = "import.note_extensions"
    public static let companionCursorOffset = "companion.cursor_offset"
    public static let companionSavedDisplaySeconds = "companion.saved_display_s"
    /// How big tälli is in its panel, in points.
    public static let companionTalliSize = "companion.talli_size_pt"
    public static let companionFinishKey = "companion.finish_key"
    public static let companionCancelKey = "companion.cancel_key"
    public static let fragmentTargetLength = "fragment.target_chars"
    public static let fragmentMaxLength = "fragment.max_chars"
    public static let embedBatchSize = "embed.batch_size"
    public static let searchRRFK = "search.rrf_k"
    public static let searchVectorCandidates = "search.vector_candidates"
    public static let searchMinSimilarity = "search.min_similarity"
    /// How many related thoughts are shown next to a thought.
    public static let relatedThoughtsCount = "explore.related_count"
    /// Meaning matches more than this below the best one are dropped (0 = off).
    public static let searchRelativeSimilarityWindow = "search.relative_similarity_window"

    /// Settings of the meaning layer (passages, embeddings, search).
    static let meaning = [
        fragmentTargetLength, fragmentMaxLength, embedBatchSize, searchRRFK, searchVectorCandidates,
        searchMinSimilarity, searchRelativeSimilarityWindow, relatedThoughtsCount,
    ]
    /// Colours, type, tälli's look and motion (docs/brand/tokens.json), shipped as `Seeds/brand.json`.
    public static let brandTokens = "brand.tokens"

    /// Every setting the code reads; the seed tests check each has a default.
    public static let all =
        [
            hotkey, sampleRate, minimumRecordingSeconds, discardSilentRecordings, idleUnloadSeconds, maxJobAttempts,
            segmentMaxPauseSeconds, retryBackoffSeconds,
            waitForModelSeconds, maintenanceIntervalSeconds, vocabularyMinSimilarityNames, vocabularyMinSimilarityOther,
            vocabularyUseContacts, textCase, summaryMinWords, summaryStemLength, archiveLocationBookmark,
            archivePendingMoveBookmark,
            lockWindow,
            exploreHotkey,
            exploreAutosaveDelaySeconds, exploreStartView, importNoteExtensions,
            companionCursorOffset,
            companionSavedDisplaySeconds, companionTalliSize, companionFinishKey, companionCancelKey, brandTokens,
        ] + meaning + Commands.all.map(\.settingKey)
}

public enum SettingsError: Error, Equatable {
    case missing(String)
    case wrongType(key: String, expected: String)
}

/// Typed read access to the `setting` table. Always reads fresh, so edits apply immediately.
public struct SettingsStore: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func value(_ key: String) throws -> JSONValue {
        let text = try database.reader.read { db in
            try String.fetchOne(db, sql: "SELECT value_json FROM setting WHERE key = ?", arguments: [key])
        }
        guard let text else { throw SettingsError.missing(key) }
        return try decodeJSON(JSONValue.self, from: text)
    }

    public func number(_ key: String) throws -> Double {
        guard let number = try value(key).doubleValue else {
            throw SettingsError.wrongType(key: key, expected: "number")
        }
        return number
    }

    public func bool(_ key: String) throws -> Bool {
        guard let bool = try value(key).boolValue else { throw SettingsError.wrongType(key: key, expected: "bool") }
        return bool
    }

    public func string(_ key: String) throws -> String {
        guard let string = try value(key).stringValue else {
            throw SettingsError.wrongType(key: key, expected: "string")
        }
        return string
    }
}
