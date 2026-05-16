// MIT License
//
// Copyright (c) 2026 Rostyslav Kobizsky
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import GRDB

/// Sole writer for the `scheduledTask` table.
///
/// **Write discipline**: Views never call this directly; ViewModels and services do.
/// Views observe through GRDBQuery `@Query` requests in `ScheduledTaskRecord.swift`.
final class ScheduledTaskStore: Sendable {
  private let writer: DatabaseWriter

  init(database: AppDatabase) {
    self.writer = database.databaseWriter
  }

  // MARK: - CRUD

  /// Insert a new task record. Caller is expected to have validated and computed `nextRunAt`.
  func insert(_ record: ScheduledTaskRecord) throws {
    try writer.write { db in
      try record.insert(db)
    }
  }

  /// Hard-delete a task. Spawned sessions are left orphaned unless the caller deletes them
  /// separately (see `SessionStore.deleteSession`).
  func delete(id: String) throws {
    try writer.write { db in
      _ = try ScheduledTaskRecord.deleteOne(db, key: id)
    }
  }

  /// Look up a task synchronously (used by the executor and reconciliation paths).
  func fetch(id: String) throws -> ScheduledTaskRecord? {
    try writer.read { db in
      try ScheduledTaskRecord.fetchOne(db, key: id)
    }
  }

  /// Fetch all currently-due, enabled tasks (used by the scheduler tick).
  func fetchDue(asOf date: Date) throws -> [ScheduledTaskRecord] {
    try writer.read { db in
      try ScheduledTaskRecord
        .filter(Column("enabled") == true && Column("nextRunAt") <= date)
        .fetchAll(db)
    }
  }

  /// Fetch all tasks (used by missed-run reconciliation on app launch).
  func fetchAll() throws -> [ScheduledTaskRecord] {
    try writer.read { db in
      try ScheduledTaskRecord.fetchAll(db)
    }
  }

  // MARK: - Enable / disable

  func setEnabled(id: String, enabled: Bool, nextRunAt: Date? = nil) throws {
    try writer.write { db in
      guard var record = try ScheduledTaskRecord.fetchOne(db, key: id) else { return }
      guard record.enabled != enabled else { return }
      record.enabled = enabled
      if let nextRunAt {
        record.nextRunAt = nextRunAt
      }
      try record.update(db)
    }
  }

  // MARK: - Run lifecycle

  /// Mark a run as started. Writes `lastRunAt`, `lastRunStatus = .running`,
  /// `lastRunSessionId`, and the computed `nextRunAt` for the following slot.
  func markRunStarted(
    id: String,
    sessionId: String,
    runAt: Date,
    nextRunAt: Date
  ) throws {
    try writer.write { db in
      guard var record = try ScheduledTaskRecord.fetchOne(db, key: id) else { return }
      record.lastRunAt = runAt
      record.lastRunStatus = ScheduledTaskRunStatus.running.rawValue
      record.lastRunMessage = nil
      record.lastRunSessionId = sessionId
      record.nextRunAt = nextRunAt
      try record.update(db)
    }
  }

  /// Transition a previously-running run to `.completed`. Used by reconciliation when
  /// an app crash left a stale `.running` row, and when a spawned session naturally
  /// transitions out of `.running`.
  func markRunCompleted(id: String) throws {
    try writer.write { db in
      guard var record = try ScheduledTaskRecord.fetchOne(db, key: id) else { return }
      guard record.lastRunStatus == ScheduledTaskRunStatus.running.rawValue else { return }
      record.lastRunStatus = ScheduledTaskRunStatus.completed.rawValue
      try record.update(db)
    }
  }

  /// Record a skipped run (overlap rule), and advance the schedule.
  func markRunSkipped(
    id: String,
    at: Date,
    nextRunAt: Date,
    reason: String
  ) throws {
    try writer.write { db in
      guard var record = try ScheduledTaskRecord.fetchOne(db, key: id) else { return }
      record.lastRunAt = at
      record.lastRunStatus = ScheduledTaskRunStatus.skipped.rawValue
      record.lastRunMessage = reason
      record.lastRunSessionId = nil
      record.nextRunAt = nextRunAt
      try record.update(db)
    }
  }

  /// Record a failed run. Auto-disables the task (per the design).
  func markRunFailed(id: String, at: Date, reason: String) throws {
    try writer.write { db in
      guard var record = try ScheduledTaskRecord.fetchOne(db, key: id) else { return }
      record.lastRunAt = at
      record.lastRunStatus = ScheduledTaskRunStatus.failed.rawValue
      record.lastRunMessage = reason
      record.lastRunSessionId = nil
      record.enabled = false
      try record.update(db)
    }
  }

  /// Update `nextRunAt` only (used by missed-run reconciliation on launch).
  func setNextRunAt(id: String, at date: Date) throws {
    try writer.write { db in
      guard var record = try ScheduledTaskRecord.fetchOne(db, key: id) else { return }
      guard record.nextRunAt != date else { return }
      record.nextRunAt = date
      try record.update(db)
    }
  }
}
