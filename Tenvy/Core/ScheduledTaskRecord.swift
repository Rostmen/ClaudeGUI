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
import GRDBQuery

/// Persistent record for a scheduled task. Sole writer is `ScheduledTaskStore`.
/// Views observe through GRDBQuery `@Query`; never write directly.
struct ScheduledTaskRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
  /// Stable primary key. UUID string.
  let id: String

  /// Display name.
  var name: String

  /// User-selected working folder. May or may not be a git repo at creation time.
  var workingDirectory: String

  /// Optional override of the worktree base directory. nil → `WorktreeService.defaultWorktreePath`.
  /// Only consulted when `useWorktree == true`.
  var customWorktreeBase: String?

  /// True when the folder was not yet a git repo at creation time; the first execution
  /// will `git init` the folder before creating the worktree. Only meaningful when
  /// `useWorktree == true`.
  var pendingGitInit: Bool

  /// When true, every execution creates a fresh git worktree off the folder's current
  /// branch. When false, executions run directly in `workingDirectory` with no git
  /// involvement — the folder doesn't even need to be a git repository.
  var useWorktree: Bool

  /// Frequency unit raw value: "minute"|"hour"|"day"|"week".
  var frequencyUnit: String

  /// Frequency value, 1...999.
  var frequencyValue: Int

  /// Time-of-day hour, required for day/week, nil otherwise.
  var timeOfDayHour: Int?
  var timeOfDayMinute: Int?

  /// Comma-joined weekday integers (1=Sun…7=Sat) for week frequency. nil/empty otherwise.
  var weekdays: String?

  /// "text" or "file".
  var promptKind: String

  /// Inline prompt text when `promptKind == "text"`.
  var promptText: String?

  /// File path when `promptKind == "file"`. File is re-read on each execution.
  var promptFilePath: String?

  /// JSON-encoded `ClaudePermissionSettings` for this task. Snapshotted onto each spawned session.
  var permissionSettings: String

  /// Whether the scheduler should fire this task.
  var enabled: Bool

  let createdAt: Date

  /// Most recent fire time (running, completed, skipped, or failed).
  var lastRunAt: Date?

  /// Raw value of `ScheduledTaskRunStatus` for the most recent fire.
  var lastRunStatus: String?

  /// Optional human-readable reason (skip cause or failure message).
  var lastRunMessage: String?

  /// `tenvySessionId` of the most recent spawned session. Best-effort, may dangle if the
  /// session record was deleted.
  var lastRunSessionId: String?

  /// Wall-clock time of the next fire. The scheduler queries this column.
  var nextRunAt: Date

  static let databaseTableName = "scheduledTask"

  // MARK: - Decoded views

  var resolvedFrequencyUnit: ScheduledTaskFrequencyUnit? {
    ScheduledTaskFrequencyUnit(rawValue: frequencyUnit)
  }

  var resolvedPromptKind: ScheduledTaskPromptKind? {
    ScheduledTaskPromptKind(rawValue: promptKind)
  }

  var resolvedLastRunStatus: ScheduledTaskRunStatus? {
    guard let lastRunStatus else { return nil }
    return ScheduledTaskRunStatus(rawValue: lastRunStatus)
  }

  var resolvedWeekdays: Set<ScheduledTaskWeekday> {
    ScheduledTaskWeekday.decode(weekdays)
  }

  var resolvedTimeOfDay: ScheduledTaskTimeOfDay? {
    guard let h = timeOfDayHour, let m = timeOfDayMinute else { return nil }
    return ScheduledTaskTimeOfDay(hour: h, minute: m)
  }

  var resolvedFrequency: ScheduledTaskFrequency? {
    guard let unit = resolvedFrequencyUnit else { return nil }
    return ScheduledTaskFrequency(
      unit: unit,
      value: frequencyValue,
      timeOfDay: resolvedTimeOfDay,
      weekdays: unit.requiresWeekdays ? resolvedWeekdays : nil
    )
  }

  var decodedPermissionSettings: ClaudePermissionSettings {
    guard let data = permissionSettings.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(ClaudePermissionSettings.self, from: data) else {
      return .empty
    }
    return decoded
  }

  // MARK: - Encoding helpers

  static func encode(_ settings: ClaudePermissionSettings) -> String {
    guard let data = try? JSONEncoder().encode(settings),
          let str = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return str
  }
}

// MARK: - GRDBQuery request types

/// Fetches all scheduled tasks ordered by creation time.
struct AllScheduledTasksRequest: ValueObservationQueryable {
  static var defaultValue: [ScheduledTaskRecord] { [] }

  func fetch(_ db: Database) throws -> [ScheduledTaskRecord] {
    try ScheduledTaskRecord
      .order(Column("createdAt").asc)
      .fetchAll(db)
  }
}

/// Fetches a single scheduled task by id.
struct ScheduledTaskByIdRequest: ValueObservationQueryable {
  static var defaultValue: ScheduledTaskRecord? { nil }

  let id: String

  func fetch(_ db: Database) throws -> ScheduledTaskRecord? {
    try ScheduledTaskRecord.fetchOne(db, key: id)
  }
}

/// Fetches all sessions spawned by a given scheduled task, newest first.
struct SessionsByScheduledTaskRequest: ValueObservationQueryable {
  static var defaultValue: [SessionRecord] { [] }

  let scheduledTaskId: String

  func fetch(_ db: Database) throws -> [SessionRecord] {
    try SessionRecord
      .filter(Column("scheduledTaskId") == scheduledTaskId)
      .order(Column("createdAt").desc)
      .fetchAll(db)
  }
}
