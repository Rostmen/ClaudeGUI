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

  /// Creates and inserts a session record with merged permissions.
  /// Handles permission merging internally — callers don't need to know about settings.
  func createSession(
    from session: ClaudeSession,
    isPlainTerminal: Bool = false,
    branchName: String? = nil,
    worktreePath: String? = nil,
    forkSourceSessionId: String? = nil
  ) {
    let mergedPermissions: ClaudePermissionSettings? = isPlainTerminal
      ? nil
      : ClaudeSettingsService.mergeForNewSession(projectPath: session.projectPath)

    let record = SessionRecord(
      tenvySessionId: session.tenvySessionId,
      workingDirectory: session.workingDirectory,
      projectPath: session.projectPath,
      title: session.title,
      branchName: branchName,
      worktreePath: worktreePath,
      isPlainTerminal: isPlainTerminal,
      isActive: true,
      forkSourceSessionId: forkSourceSessionId,
      createdAt: Date(),
      lastModifiedAt: Date(),
      permissionSettings: mergedPermissions.flatMap { SessionRecord.encode($0) }
    )
    try? insertSession(record)
  }

  // MARK: - Claude Session ID Mapping

  /// Map a Claude session ID to a terminal ID (one-time per session).
  /// Skips the write if the mapping is already set — avoids triggering
  /// GRDB @Query observers on every hook event.
  func mapClaudeSessionId(tenvySessionId: String, claudeSessionId: String) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: tenvySessionId) {
        guard record.claudeSessionId != claudeSessionId else { return }
        record.claudeSessionId = claudeSessionId
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  // MARK: - Lifecycle

  /// Mark a session as inactive. Called when the terminal is closed.
  func deactivateSession(tenvySessionId: String) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: tenvySessionId) {
        record.isActive = false
        record.hookState = nil
        record.currentTool = nil
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  /// Delete a session record entirely.
  func deleteSession(tenvySessionId: String) throws {
    try writer.write { db in
      _ = try SessionRecord.deleteOne(db, key: tenvySessionId)
    }
  }

  // MARK: - Session File Discovery

  /// Upsert session metadata discovered from a `.jsonl` file.
  /// Called by SessionManager after scanning Claude's session files.
  /// Does NOT overwrite `tenvySessionId` if a record already exists for this Claude session ID.
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
        // Update only discoverable fields — don't touch tenvySessionId or paths
        existing.title = title
        existing.sessionFilePath = filePath
        existing.lastModifiedAt = lastModified
        try existing.update(db)
      } else {
        // New session discovered from file (not created in app) —
        // use claudeSessionId as tenvySessionId since there's no Tenvy terminal for it
        let record = SessionRecord(
          tenvySessionId: claudeSessionId,
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
  func updateTitle(tenvySessionId: String, title: String) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: tenvySessionId) {
        record.title = title
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  // MARK: - Git Branch

  /// Update the git branch for a session.
  func updateBranch(tenvySessionId: String, branchName: String?) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: tenvySessionId) {
        record.branchName = branchName
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  // MARK: - Permission Settings

  /// Update permission settings for a session.
  func updatePermissionSettings(tenvySessionId: String, settings: ClaudePermissionSettings) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: tenvySessionId) {
        record.permissionSettings = SessionRecord.encode(settings)
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  /// Reset permission settings to nil (re-inherit from global + project on next launch).
  func resetPermissionSettings(tenvySessionId: String) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: tenvySessionId) {
        record.permissionSettings = nil
        record.launchedPermissionsHash = nil
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }

  /// Update the launched permissions hash after a session starts or restarts.
  func updateLaunchedPermissionsHash(tenvySessionId: String, hash: String) throws {
    try writer.write { db in
      if var record = try SessionRecord.fetchOne(db, key: tenvySessionId) {
        record.launchedPermissionsHash = hash
        record.lastModifiedAt = Date()
        try record.update(db)
      }
    }
  }
}
