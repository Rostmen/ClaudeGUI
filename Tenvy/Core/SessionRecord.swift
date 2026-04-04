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

/// Persistent session record stored in the local SQLite database.
/// This is the source of truth for session identity, paths, and hook state.
/// Views observe these records via `@Query`; writes go through `SessionStore`.
struct SessionRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
  var id: String { terminalId }

  /// Stable terminal identifier — primary key, set at creation, never changes.
  let terminalId: String

  /// Claude CLI's own session ID. Set when the first hook event arrives
  /// carrying both `session_id` and `terminal_id`, providing instant reliable mapping.
  var claudeSessionId: String?

  /// Working directory where the terminal was launched. Immutable from creation.
  let workingDirectory: String

  /// Project path (repo root or worktree root). Immutable from creation.
  let projectPath: String

  /// Display title — initially "New Session", updated from Claude's session file.
  var title: String

  /// Git branch at the time of creation.
  var branchName: String?

  /// Worktree path if this session was created via a worktree.
  var worktreePath: String?

  /// Current hook state (processing, thinking, waiting, waitingPermission, etc.)
  /// Stored as the raw `HookState` string value. Updated by `SessionStore`.
  var hookState: String?

  /// Tool currently being used by Claude (from hook events).
  var currentTool: String?

  /// Whether this is a plain terminal (not a Claude session).
  let isPlainTerminal: Bool

  /// Whether this session has a running terminal in the app.
  var isActive: Bool

  /// If this session was forked, the source session's Claude ID.
  var forkSourceSessionId: String?

  /// When the session was created in the app.
  let createdAt: Date

  /// Last time the session was updated (hook event, title change, etc.)
  var lastModifiedAt: Date

  /// Path to the `.jsonl` session file once discovered by SessionManager.
  var sessionFilePath: String?

  static let databaseTableName = "sessionRecord"

  /// Resolved HookState from the stored raw string.
  var resolvedHookState: HookState? {
    guard let hookState else { return nil }
    return HookState(rawValue: hookState)
  }
}

// MARK: - GRDBQuery Request Types

import GRDBQuery

/// Fetches all session records ordered by last modified date.
struct AllSessionsRequest: ValueObservationQueryable {
  static var defaultValue: [SessionRecord] { [] }

  func fetch(_ db: Database) throws -> [SessionRecord] {
    try SessionRecord
      .order(Column("lastModifiedAt").desc)
      .fetchAll(db)
  }
}

/// Fetches only active session records.
struct ActiveSessionsRequest: ValueObservationQueryable {
  static var defaultValue: [SessionRecord] { [] }

  func fetch(_ db: Database) throws -> [SessionRecord] {
    try SessionRecord
      .filter(Column("isActive") == true)
      .order(Column("lastModifiedAt").desc)
      .fetchAll(db)
  }
}

/// Fetches a single session record by terminal ID.
struct SessionByTerminalIdRequest: ValueObservationQueryable {
  static var defaultValue: SessionRecord? { nil }

  let terminalId: String

  func fetch(_ db: Database) throws -> SessionRecord? {
    try SessionRecord.fetchOne(db, key: terminalId)
  }
}

/// Fetches a single session record by Claude session ID.
struct SessionByClaudeIdRequest: ValueObservationQueryable {
  static var defaultValue: SessionRecord? { nil }

  let claudeSessionId: String

  func fetch(_ db: Database) throws -> SessionRecord? {
    try SessionRecord
      .filter(Column("claudeSessionId") == claudeSessionId)
      .fetchOne(db)
  }
}
