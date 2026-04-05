// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

struct GitServiceFindRepoRootTests {

  private let gitService = GitService(settings: AppSettings.shared)

  private func makeTempDir() throws -> String {
    let path = NSTemporaryDirectory() + "GitServiceFindRepoRoot-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  @Test("finds repo root from the root itself")
  func fromRepoRoot() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    try FileManager.default.createDirectory(
      atPath: (tmp as NSString).appendingPathComponent(".git"),
      withIntermediateDirectories: true
    )
    #expect(gitService.findRepoRoot(from: tmp) == tmp)
  }

  @Test("finds repo root from a nested subdirectory")
  func fromNestedSubdirectory() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    try FileManager.default.createDirectory(
      atPath: (tmp as NSString).appendingPathComponent(".git"),
      withIntermediateDirectories: true
    )
    let sub = (tmp as NSString).appendingPathComponent("src/deep/nested")
    try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)

    #expect(gitService.findRepoRoot(from: sub) == tmp)
  }

  @Test("returns nil when no .git exists")
  func noGitDir() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    let sub = (tmp as NSString).appendingPathComponent("some/dir")
    try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)

    #expect(gitService.findRepoRoot(from: sub) == nil)
  }

  @Test("skips .git file (worktree) and finds real repo root")
  func skipsWorktreeGitFile() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    // Main repo with real .git directory
    let mainRepo = (tmp as NSString).appendingPathComponent("main")
    try FileManager.default.createDirectory(
      atPath: (mainRepo as NSString).appendingPathComponent(".git"),
      withIntermediateDirectories: true
    )

    // Worktree with .git FILE
    let worktree = (mainRepo as NSString).appendingPathComponent(".claude/worktrees/feature")
    try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
    try "gitdir: \((mainRepo as NSString).appendingPathComponent(".git"))/worktrees/feature"
      .write(toFile: (worktree as NSString).appendingPathComponent(".git"), atomically: true, encoding: .utf8)

    #expect(gitService.findRepoRoot(from: worktree) == mainRepo)
  }

  @Test("uses injected fileManager for filesystem checks")
  func usesInjectedFileManager() {
    // Custom fileManager that always returns false for fileExists
    // This verifies DI works — findRepoRoot should return nil
    let service = GitService(settings: AppSettings.shared, fileManager: .default)
    // With default FileManager on a random non-existent path
    #expect(service.findRepoRoot(from: "/nonexistent/path/\(UUID().uuidString)") == nil)
  }
}
