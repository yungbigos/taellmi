import CSQLiteVec
import Foundation
import GRDB

/// The app's SQLite database. Holds config and the index of entries (entries themselves live on disk).
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    public var reader: any DatabaseReader { writer }

    /// Wraps a GRDB connection and brings the schema up to date.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Migrations.migrator.migrate(writer)
    }

    /// Opens (or creates) the database file, using WAL mode for concurrent reads.
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: url.path, configuration: configuration()))
    }

    /// Connection settings every database of the app needs, including the vector search functions.
    public static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // sqlite-vec is compiled into the app (no extension loading), so the sandbox is no obstacle.
            let code = sqlite3_vec_init(db.sqliteConnection, nil, nil)
            guard code == SQLITE_OK else { throw DatabaseError(resultCode: ResultCode(rawValue: code)) }
        }
        return configuration
    }
}
