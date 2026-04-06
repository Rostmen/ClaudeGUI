// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

struct GitServiceFindRepoRootTests {

  private func makeGitService() -> GitService {
    GitService(settings: TestAppSettings.make())
  }

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
    let gitService = makeGitService()
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
    let gitService = makeGitService()
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
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    let sub = (tmp as NSString).appendingPathComponent("some/dir")
    try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)

    #expect(gitService.findRepoRoot(from: sub) == nil)
  }

  @Test("skips .git file (worktree) and finds real repo root")
  func skipsWorktreeGitFile() throws {
    let gitService = makeGitService()
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

  @Test("follows gitdir pointer when worktree is outside repo tree")
  func followsGitdirOutsideRepoTree() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    // Main repo at <tmp>/repos/MyApp
    let mainRepo = (tmp as NSString).appendingPathComponent("repos/MyApp")
    let mainGitDir = (mainRepo as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: mainGitDir, withIntermediateDirectories: true)

    // Worktree git dir inside main .git
    let worktreeGitDir = (mainGitDir as NSString).appendingPathComponent("worktrees/feature-branch")
    try FileManager.default.createDirectory(atPath: worktreeGitDir, withIntermediateDirectories: true)
    // commondir points back to main .git
    try "../.."
      .write(toFile: (worktreeGitDir as NSString).appendingPathComponent("commondir"),
             atomically: true, encoding: .utf8)

    // Worktree checkout in a COMPLETELY DIFFERENT directory tree
    let worktreeCheckout = (tmp as NSString).appendingPathComponent("worktrees/MyApp-feature")
    try FileManager.default.createDirectory(atPath: worktreeCheckout, withIntermediateDirectories: true)
    // .git file points to the worktree git dir
    try "gitdir: \(worktreeGitDir)"
      .write(toFile: (worktreeCheckout as NSString).appendingPathComponent(".git"),
             atomically: true, encoding: .utf8)

    // findRepoRoot should follow gitdir → commondir → main repo
    #expect(gitService.findRepoRoot(from: worktreeCheckout) == mainRepo)
  }

  @Test("returns nil for nonexistent path")
  func nonexistentPath() {
    let gitService = makeGitService()
    #expect(gitService.findRepoRoot(from: "/nonexistent/path/\(UUID().uuidString)") == nil)
  }
}
