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
import Testing
@testable import Tenvy

/// Tests for `GitService` — findRepoRoot, defaultWorktreePath, hasSubmodules, worktreeWorkingDirectory.
struct WorktreeServiceTests {

  private let gitService = GitService(settings: AppSettings.shared)

  /// Helper: creates a temporary directory tree and returns the root path.
  private func makeTempDir() throws -> String {
    let path = NSTemporaryDirectory() + "WorktreeServiceTests-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  // MARK: - findRepoRoot

  @Test func findRepoRoot_realRepo() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    // Create a real .git directory
    let gitDir = (tmp as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)

    // From the repo root itself
    #expect(gitService.findRepoRoot(from: tmp) == tmp)

    // From a subdirectory
    let sub = (tmp as NSString).appendingPathComponent("src/deep/nested")
    try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
    #expect(gitService.findRepoRoot(from: sub) == tmp)
  }

  @Test func findRepoRoot_worktreeSkipsGitFile() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    // Simulate main repo at <tmp>/main with a real .git directory
    let mainRepo = (tmp as NSString).appendingPathComponent("main")
    let mainGitDir = (mainRepo as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: mainGitDir, withIntermediateDirectories: true)

    // Simulate worktree at <tmp>/main/.claude/worktrees/feature with a .git FILE
    let worktree = (mainRepo as NSString).appendingPathComponent(".claude/worktrees/feature")
    try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
    let worktreeGitFile = (worktree as NSString).appendingPathComponent(".git")
    try "gitdir: \(mainGitDir)/worktrees/feature".write(toFile: worktreeGitFile, atomically: true, encoding: .utf8)

    // findRepoRoot from the worktree should return the main repo, not the worktree
    #expect(gitService.findRepoRoot(from: worktree) == mainRepo)
  }

  @Test func findRepoRoot_nestedWorktreeSkipsBothGitFiles() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    // Main repo
    let mainRepo = (tmp as NSString).appendingPathComponent("main")
    let mainGitDir = (mainRepo as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: mainGitDir, withIntermediateDirectories: true)

    // First worktree (child of main) with .git file
    let wt1 = (mainRepo as NSString).appendingPathComponent(".claude/worktrees/fix-focus")
    try FileManager.default.createDirectory(atPath: wt1, withIntermediateDirectories: true)
    let wt1GitFile = (wt1 as NSString).appendingPathComponent(".git")
    try "gitdir: \(mainGitDir)/worktrees/fix-focus".write(toFile: wt1GitFile, atomically: true, encoding: .utf8)

    // Second worktree NESTED inside first (the bug scenario) with .git file
    let wt2 = (wt1 as NSString).appendingPathComponent(".claude/worktrees/fix-focus-2")
    try FileManager.default.createDirectory(atPath: wt2, withIntermediateDirectories: true)
    let wt2GitFile = (wt2 as NSString).appendingPathComponent(".git")
    try "gitdir: \(mainGitDir)/worktrees/fix-focus-2".write(toFile: wt2GitFile, atomically: true, encoding: .utf8)

    // From the nested worktree, should resolve all the way up to main repo
    #expect(gitService.findRepoRoot(from: wt2) == mainRepo)

    // From a subdirectory inside the nested worktree
    let deepDir = (wt2 as NSString).appendingPathComponent("src/views")
    try FileManager.default.createDirectory(atPath: deepDir, withIntermediateDirectories: true)
    #expect(gitService.findRepoRoot(from: deepDir) == mainRepo)
  }

  @Test func findRepoRoot_noGitReturnsNil() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    // No .git anywhere — should return nil
    let sub = (tmp as NSString).appendingPathComponent("a/b/c")
    try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
    #expect(gitService.findRepoRoot(from: sub) == nil)
  }

  // MARK: - defaultWorktreePath

  @Test func defaultWorktreePath_usesRepoRoot() throws {
    let repoRoot = "/Users/test/Projects/MyApp"
    let result = gitService.defaultWorktreePath(repoRoot: repoRoot, branchName: "fix-focus-2")
    #expect(result == "/Users/test/Projects/MyApp/.claude/worktrees/fix-focus-2")
  }

  @Test func defaultWorktreePath_sanitizesSlashes() throws {
    let repoRoot = "/Users/test/Projects/MyApp"
    let result = gitService.defaultWorktreePath(repoRoot: repoRoot, branchName: "feature/auth/login")
    #expect(result == "/Users/test/Projects/MyApp/.claude/worktrees/feature-auth-login")
  }

  // MARK: - Integration: findRepoRoot + defaultWorktreePath

  @Test func worktreePathFromWorktreeResolvesToMainRepo() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    // Main repo
    let mainRepo = (tmp as NSString).appendingPathComponent("MyApp")
    let mainGitDir = (mainRepo as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: mainGitDir, withIntermediateDirectories: true)

    // Existing worktree with .git file
    let worktree = (mainRepo as NSString).appendingPathComponent(".claude/worktrees/fix-focus")
    try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
    let gitFile = (worktree as NSString).appendingPathComponent(".git")
    try "gitdir: \(mainGitDir)/worktrees/fix-focus".write(toFile: gitFile, atomically: true, encoding: .utf8)

    // Simulate the split flow: find repo root from worktree, then build new worktree path
    let repoRoot = gitService.findRepoRoot(from: worktree)
    #expect(repoRoot == mainRepo)

    let newPath = gitService.defaultWorktreePath(repoRoot: repoRoot!, branchName: "fix-focus-2")
    #expect(newPath == (mainRepo as NSString).appendingPathComponent(".claude/worktrees/fix-focus-2"))

    // NOT nested inside the first worktree
    #expect(!newPath.contains("fix-focus/.claude/worktrees"))
  }

  // MARK: - worktreeWorkingDirectory

  @Test func worktreeWorkingDirectory_regularSubfolder() {
    // Source in a subfolder of the repo (not a worktree)
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/repo/.claude/worktrees/new-feature",
      sourceProjectPath: "/repo",
      sourceWorkingDirectory: "/repo/src/ios"
    )
    #expect(result == "/repo/.claude/worktrees/new-feature/src/ios")
  }

  @Test func worktreeWorkingDirectory_sourceIsRepoRoot() {
    // Source is at the repo root — no offset
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/repo/.claude/worktrees/new-feature",
      sourceProjectPath: "/repo",
      sourceWorkingDirectory: "/repo"
    )
    #expect(result == "/repo/.claude/worktrees/new-feature")
  }

  @Test func worktreeWorkingDirectory_sourceIsWorktreeRoot() {
    // Source is at a worktree root — no subfolder offset, just the new worktree path
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/repo/.claude/worktrees/fix-focus-2",
      sourceProjectPath: "/repo/.claude/worktrees/fix-focus",
      sourceWorkingDirectory: "/repo/.claude/worktrees/fix-focus"
    )
    #expect(result == "/repo/.claude/worktrees/fix-focus-2")
  }

  @Test func worktreeWorkingDirectory_sourceIsWorktreeSubfolder() {
    // Source is in a subfolder of a worktree — preserve the subfolder offset
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/repo/.claude/worktrees/fix-focus-2",
      sourceProjectPath: "/repo/.claude/worktrees/fix-focus",
      sourceWorkingDirectory: "/repo/.claude/worktrees/fix-focus/src/views"
    )
    #expect(result == "/repo/.claude/worktrees/fix-focus-2/src/views")
  }

  @Test func worktreeWorkingDirectory_doesNotNestWorktreePaths() {
    // Splitting from a worktree must NOT nest the worktree path
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/repo/.claude/worktrees/fix-focus-2",
      sourceProjectPath: "/repo/.claude/worktrees/fix-worktree-dialog-focus",
      sourceWorkingDirectory: "/repo/.claude/worktrees/fix-worktree-dialog-focus"
    )
    // Must NOT contain nested worktree paths
    #expect(!result.contains("fix-worktree-dialog-focus/.claude/worktrees"))
    #expect(result == "/repo/.claude/worktrees/fix-focus-2")
  }

  // MARK: - hasSubmodules

  @Test func hasSubmodules_returnsTrueWhenGitmodulesExists() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    let gitmodulesPath = (tmp as NSString).appendingPathComponent(".gitmodules")
    try "[submodule \"lib\"]\n\tpath = lib\n\turl = https://example.com/lib.git\n"
      .write(toFile: gitmodulesPath, atomically: true, encoding: .utf8)

    #expect(gitService.hasSubmodules(repoRoot: tmp) == true)
  }

  @Test func hasSubmodules_returnsFalseWhenNoGitmodules() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    #expect(gitService.hasSubmodules(repoRoot: tmp) == false)
  }

  @Test func hasSubmodules_returnsFalseWhenGitmodulesIsEmpty() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    let gitmodulesPath = (tmp as NSString).appendingPathComponent(".gitmodules")
    try "".write(toFile: gitmodulesPath, atomically: true, encoding: .utf8)

    #expect(gitService.hasSubmodules(repoRoot: tmp) == false)
  }

  @Test func worktreeWorkingDirectory_sourceOutsideProject() {
    // Source is outside the project — just return worktree path
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/repo/.claude/worktrees/new-feature",
      sourceProjectPath: "/repo",
      sourceWorkingDirectory: "/other/project"
    )
    #expect(result == "/repo/.claude/worktrees/new-feature")
  }
}
