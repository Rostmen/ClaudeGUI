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

/// Manages the local SQLite database for persistent session storage.
///
/// Uses `DatabasePool` (WAL mode) for concurrent reads from SwiftUI views
/// and writes from services/ViewModels. Views observe via GRDBQuery's `@Query`;
/// all writes go through `SessionStore`.
struct AppDatabase {

  /// The underlying database pool.
  private let dbPool: DatabasePool

  /// Reader for GRDBQuery's `@Query` property wrapper.
  var databaseReader: DatabaseReader { dbPool }

  /// Writer for `SessionStore` to perform mutations.
  var databaseWriter: DatabaseWriter { dbPool }

  // MARK: - Shared Instance

  /// Live app database stored in Application Support.
  static let shared = try! AppDatabase(path: AppDatabase.defaultDatabasePath())

  // MARK: - Init

  /// Creates a database at the given file path and applies migrations.
  init(path: String) throws {
    var config = Configuration()
    #if DEBUG
    config.prepareDatabase { db in
      db.trace { print("SQL: \($0)") }
    }
    #endif
    dbPool = try DatabasePool(path: path, configuration: config)
    try migrator.migrate(dbPool)
  }

  /// In-memory database for tests and SwiftUI previews.
  static func inMemory() throws -> AppDatabase {
    let pool = try DatabasePool(path: ":memory:")
    let db = AppDatabase(pool: pool)
    try db.migrator.migrate(pool)
    return db
  }

  private init(pool: DatabasePool) {
    self.dbPool = pool
  }

  // MARK: - Migrations

  private var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1_createSessionRecord") { db in
      try db.create(table: "sessionRecord") { t in
        t.primaryKey("tenvySessionId", .text)
        t.column("claudeSessionId", .text)
        t.column("workingDirectory", .text).notNull()
        t.column("projectPath", .text).notNull()
        t.column("title", .text).notNull().defaults(to: "New Session")
        t.column("branchName", .text)
        t.column("worktreePath", .text)
        t.column("hookState", .text)
        t.column("currentTool", .text)
        t.column("isPlainTerminal", .boolean).notNull().defaults(to: false)
        t.column("isActive", .boolean).notNull().defaults(to: false)
        t.column("forkSourceSessionId", .text)
        t.column("createdAt", .datetime).notNull()
        t.column("lastModifiedAt", .datetime).notNull()
        t.column("sessionFilePath", .text)
      }
    }

    migrator.registerMigration("v2_addPermissionSettings") { db in
      try db.alter(table: "sessionRecord") { t in
        t.add(column: "permissionSettings", .text)
        t.add(column: "launchedPermissionsHash", .text)
      }
    }

    migrator.registerMigration("v3_renameTerminalIdToTenvySessionId") { db in
      // v1 was updated in-place to use tenvySessionId directly.
      // Only rename if the old column still exists (pre-v3 databases).
      let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(sessionRecord)")
      let hasTerminalId = columns.contains { $0["name"] as String == "terminalId" }
      if hasTerminalId {
        try db.execute(sql: "ALTER TABLE sessionRecord RENAME COLUMN terminalId TO tenvySessionId")
      }
    }

    return migrator
  }

  // MARK: - Database Path

  private static func defaultDatabasePath() -> String {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!.appendingPathComponent("Tenvy")

    try? FileManager.default.createDirectory(
      at: appSupport,
      withIntermediateDirectories: true
    )

    return appSupport.appendingPathComponent("sessions.sqlite").path
  }
}
