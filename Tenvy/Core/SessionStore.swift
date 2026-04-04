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

/// The sole service responsible for writing to the sessions database.
///
/// **Write discipline**: Views never call `SessionStore` directly.
/// Only ViewModels and services perform mutations through this class.
/// Views observe the database read-only via GRDBQuery's `@Query`.
final class SessionStore: Sendable {
  private let writer: DatabaseWriter

  init(database: AppDatabase) {
    self.writer = database.databaseWriter
  }

  // MARK: - Insert

  /// Insert a new session record. Called by ViewModels when creating a session.
  func insertSession(_ record: SessionRecord) throws {
    try writer.write { db in
      try record.insert(db)
    }
  }

  // MARK: - Claude Session ID Mapping

  /// Map a Claude session ID to a terminal ID (one-time per session).
  /// Skips the write if the mapping is already set — avoids triggering
  /// GRDB @Query observers on every hook event.
  func mapClaudeSessionId(terminalId: String, claudeSessionId: String) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: terminalId) {
        guard record.claudeSessionId != claudeSessionId else { return }
        record.claudeSessionId = claudeSessionId
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  // MARK: - Lifecycle

  /// Mark a session as inactive. Called when the terminal is closed.
  func deactivateSession(terminalId: String) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: terminalId) {
        record.isActive = false
        record.hookState = nil
        record.currentTool = nil
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  /// Delete a session record entirely.
  func deleteSession(terminalId: String) throws {
    try writer.write { db in
      _ = try SessionRecord.deleteOne(db, key: terminalId)
    }
  }

  // MARK: - Session File Discovery

  /// Upsert session metadata discovered from a `.jsonl` file.
  /// Called by SessionManager after scanning Claude's session files.
  /// Does NOT overwrite `terminalId` if a record already exists for this Claude session ID.
  func upsertFromSessionFile(
    claudeSessionId: String,
    title: String,
    filePath: String?,
    lastModified: Date,
    workingDirectory: String,
    projectPath: String
  ) throws {
    try writer.write { db in
      // Check if we already have a record with this Claude session ID
      if var existing = try SessionRecord
        .filter(Column("claudeSessionId") == claudeSessionId)
        .fetchOne(db) {
        // Skip update if nothing changed — avoids triggering @Query observers
        guard existing.title != title
                || existing.sessionFilePath != filePath
                || existing.lastModifiedAt != lastModified else { return }
        // Update only discoverable fields — don't touch terminalId or paths
        existing.title = title
        existing.sessionFilePath = filePath
        existing.lastModifiedAt = lastModified
        try existing.update(db)
      } else {
        // New session discovered from file (not created in app) —
        // use claudeSessionId as terminalId since there's no Tenvy terminal for it
        let record = SessionRecord(
          terminalId: claudeSessionId,
          claudeSessionId: claudeSessionId,
          workingDirectory: workingDirectory,
          projectPath: projectPath,
          title: title,
          isPlainTerminal: false,
          isActive: false,
          createdAt: lastModified,
          lastModifiedAt: lastModified,
          sessionFilePath: filePath
        )
        try record.insert(db)
      }
    }
  }

  // MARK: - Title Updates

  /// Update the title for a session. Called after renaming.
  func updateTitle(terminalId: String, title: String) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: terminalId) {
        record.title = title
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  // MARK: - Git Branch

  /// Update the git branch for a session.
  func updateBranch(terminalId: String, branchName: String?) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: terminalId) {
        record.branchName = branchName
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }
}
