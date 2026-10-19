import Domain
import Foundation
import GRDB
import Persistence

/// Names of the settings the code reads. Values (and defaults) live in the database and seed files.
public enum SettingKeys {
    public static let hotkey = "capture.hotkey"
    public static let sampleRate = "capture.sample_rate"
    public static let idleUnloadSeconds = "models.idle_unload_s"
    public static let maxJobAttempts = "pipeline.max_attempts"
    public static let segmentMaxPauseSeconds = "transcription.segment_max_pause_s"
    public static let retryBackoffSeconds = "pipeline.retry_backoff_s"
    public static let waitForModelSeconds = "pipeline.wait_for_model_s"
    public static let maintenanceIntervalSeconds = "app.maintenance_interval_s"

    public static let all = [
        hotkey, sampleRate, idleUnloadSeconds, maxJobAttempts, segmentMaxPauseSeconds, retryBackoffSeconds,
        waitForModelSeconds, maintenanceIntervalSeconds,
    ]
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

    public func string(_ key: String) throws -> String {
        guard let string = try value(key).stringValue else {
            throw SettingsError.wrongType(key: key, expected: "string")
        }
        return string
    }
}
