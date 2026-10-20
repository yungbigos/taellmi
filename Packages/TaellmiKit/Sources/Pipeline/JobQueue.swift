import Domain
import Foundation
import GRDB
import Persistence

/// A unit of background work for one entry, stored in SQLite so it survives quit and crash.
public struct Job: Sendable, Equatable {
    public enum State: String, Sendable {
        case pending, running, done, failed
    }

    public var id: Int64
    public var entryID: String
    public var step: String
    public var state: State
    public var attempts: Int
    public var lastError: String?
}

/// The durable job table.
public struct JobQueue: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Adds a pending job per step, skipping steps the entry already has.
    public func enqueue(entryID: String, steps: [String], now: Date = Date()) throws {
        try database.writer.write { db in
            for step in steps {
                try db.execute(
                    sql: """
                        INSERT INTO job (entry_id, step, state, attempts, created_at, updated_at)
                        VALUES (?, ?, 'pending', 0, ?, ?)
                        ON CONFLICT(entry_id, step) DO NOTHING
                        """,
                    arguments: [entryID, step, now, now])
            }
        }
    }

    /// Runs the steps again for an Entry whose input changed: finished steps become pending, missing steps
    /// are added. Running jobs are left alone, and so are failed ones, so a broken step is not retried forever.
    public func requeue(entryID: String, steps: [String], now: Date = Date()) throws {
        try database.writer.write { db in
            for step in steps {
                try db.execute(
                    sql: """
                        INSERT INTO job (entry_id, step, state, attempts, created_at, updated_at)
                        VALUES (?, ?, 'pending', 0, ?, ?)
                        ON CONFLICT(entry_id, step) DO UPDATE SET state = 'pending', attempts = 0, last_error = NULL,
                            not_before = NULL, updated_at = excluded.updated_at
                        WHERE job.state = 'done'
                        """,
                    arguments: [entryID, step, now, now])
            }
        }
    }

    /// Claims the next runnable job: pending, past its `not_before`, and every earlier step of the
    /// same entry is finished, done or failed for good. Earlier pipeline steps go first across all thoughts, so
    /// a new recording is transcribed before a backlog of slow later steps (e.g. understanding old thoughts). A later step then works with whatever input exists
    /// (e.g. Text you typed into a recording that could not be transcribed). Claiming counts as an attempt.
    public func claimNext(now: Date = Date()) throws -> Job? {
        try database.writer.write { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT j.* FROM job j LEFT JOIN pipeline_step p ON p.step = j.step
                        WHERE j.state = 'pending'
                          AND (j.not_before IS NULL OR j.not_before <= ?)
                          AND NOT EXISTS (
                            SELECT 1 FROM job e WHERE e.entry_id = j.entry_id AND e.id < j.id
                                AND e.state NOT IN ('done', 'failed'))
                        ORDER BY COALESCE(p.ordinal, 0), j.id LIMIT 1
                        """, arguments: [now])
            else { return nil }
            var job = Self.job(from: row)
            job.state = .running
            job.attempts += 1
            try db.execute(
                sql: "UPDATE job SET state = 'running', attempts = ?, updated_at = ? WHERE id = ?",
                arguments: [job.attempts, now, job.id])
            return job
        }
    }

    public func markDone(_ job: Job, now: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE job SET state = 'done', last_error = NULL, updated_at = ? WHERE id = ?",
                arguments: [now, job.id])
        }
    }

    /// Records a failure. The job is retried after `backoff × attempts` seconds until it has used `maxAttempts`.
    public func markFailed(_ job: Job, error: String, maxAttempts: Int, backoff: TimeInterval, now: Date = Date())
        throws
    {
        let state: Job.State = job.attempts >= maxAttempts ? .failed : .pending
        let notBefore = now.addingTimeInterval(backoff * Double(job.attempts))
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE job SET state = ?, last_error = ?, not_before = ?, updated_at = ? WHERE id = ?",
                arguments: [state.rawValue, error, notBefore, now, job.id])
        }
    }

    /// The job could not start for a reason outside itself (e.g. no model installed yet).
    /// It goes back to pending without using up an attempt and is tried again after `retryAfter`.
    public func markWaiting(_ job: Job, reason: String, retryAfter: TimeInterval, now: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE job SET state = 'pending', attempts = MAX(attempts - 1, 0), last_error = ?,
                        not_before = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [reason, now.addingTimeInterval(retryAfter), now, job.id])
        }
    }

    /// Jobs left `running` by a crash or quit become pending again, unless they already used every
    /// attempt (a job that crashes the app must not be retried forever).
    public func recoverInterrupted(maxAttempts: Int) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE job SET state = CASE WHEN attempts >= ? THEN 'failed' ELSE 'pending' END,
                        last_error = CASE WHEN attempts >= ? THEN 'interrupted on every attempt' ELSE last_error END
                    WHERE state = 'running'
                    """,
                arguments: [maxAttempts, maxAttempts])
        }
    }

    public func jobs(entryID: String) throws -> [Job] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM job WHERE entry_id = ? ORDER BY id", arguments: [entryID])
                .map(Self.job(from:))
        }
    }

    private static func job(from row: Row) -> Job {
        Job(
            id: row["id"], entryID: row["entry_id"], step: row["step"],
            state: Job.State(rawValue: row["state"]) ?? .pending, attempts: row["attempts"],
            lastError: row["last_error"])
    }
}
