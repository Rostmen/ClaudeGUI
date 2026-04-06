// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

struct GitServiceBranchTests {

  private func makeGitService() -> GitService {
    GitService(settings: TestAppSettings.make())
  }

  private func makeTempDir() throws -> String {
    let path = NSTemporaryDirectory() + "GitServiceBranch-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  /// Creates a minimal .git directory with HEAD pointing to a branch.
  private func createGitDir(at path: String, branch: String = "main") throws {
    let gitDir = (path as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
    try "ref: refs/heads/\(branch)".write(
      toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
      atomically: true, encoding: .utf8
    )
  }

  /// Creates a loose ref for a branch.
  private func createBranchRef(gitDir: String, branch: String, sha: String = "abc1234567890") throws {
    let refPath = (gitDir as NSString).appendingPathComponent("refs/heads/\(branch)")
    try FileManager.default.createDirectory(
      atPath: (refPath as NSString).deletingLastPathComponent,
      withIntermediateDirectories: true
    )
    try sha.write(toFile: refPath, atomically: true, encoding: .utf8)
  }

  // MARK: - currentBranch

  @Test("returns branch name from HEAD ref")
  func currentBranchFromRef() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createGitDir(at: tmp, branch: "feature/auth")

    #expect(gitService.currentBranch(at: tmp) == "feature/auth")
  }

  @Test("returns short SHA for detached HEAD")
  func currentBranchDetachedHead() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    let gitDir = (tmp as NSString).appendingPathComponent(".git")
    try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
    try "abc1234567890def".write(
      toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
      atomically: true, encoding: .utf8
    )

    #expect(gitService.currentBranch(at: tmp) == "abc1234")
  }

  @Test("returns nil when no .git exists")
  func currentBranchNoGit() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    #expect(gitService.currentBranch(at: tmp) == nil)
  }

  @Test("reads branch from subdirectory")
  func currentBranchFromSubdir() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createGitDir(at: tmp, branch: "develop")
    let sub = (tmp as NSString).appendingPathComponent("src/deep")
    try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)

    #expect(gitService.currentBranch(at: sub) == "develop")
  }

  // MARK: - listLocalBranches

  @Test("lists loose branch refs")
  func listLooseBranches() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createGitDir(at: tmp, branch: "main")
    let gitDir = (tmp as NSString).appendingPathComponent(".git")
    try createBranchRef(gitDir: gitDir, branch: "main")
    try createBranchRef(gitDir: gitDir, branch: "feature/auth")
    try createBranchRef(gitDir: gitDir, branch: "fix-bug")

    let branches = gitService.listLocalBranches(at: tmp)
    #expect(branches.contains("main"))
    #expect(branches.contains("feature/auth"))
    #expect(branches.contains("fix-bug"))
    #expect(branches.count == 3)
  }

  @Test("lists branches from packed-refs")
  func listPackedBranches() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createGitDir(at: tmp, branch: "main")
    let gitDir = (tmp as NSString).appendingPathComponent(".git")

    let packedRefs = """
    # pack-refs with: peeled fully-peeled sorted
    abc123 refs/heads/main
    def456 refs/heads/release/v2
    789abc refs/tags/v1.0
    """
    try packedRefs.write(
      toFile: (gitDir as NSString).appendingPathComponent("packed-refs"),
      atomically: true, encoding: .utf8
    )

    let branches = gitService.listLocalBranches(at: tmp)
    #expect(branches.contains("main"))
    #expect(branches.contains("release/v2"))
    #expect(!branches.contains("v1.0")) // tags excluded
  }

  @Test("returns empty for non-git directory")
  func listBranchesNoGit() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    #expect(gitService.listLocalBranches(at: tmp) == [])
  }

  @Test("returns sorted branches")
  func listBranchesSorted() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createGitDir(at: tmp, branch: "main")
    let gitDir = (tmp as NSString).appendingPathComponent(".git")
    try createBranchRef(gitDir: gitDir, branch: "zebra")
    try createBranchRef(gitDir: gitDir, branch: "alpha")
    try createBranchRef(gitDir: gitDir, branch: "middle")

    let branches = gitService.listLocalBranches(at: tmp)
    #expect(branches == ["alpha", "middle", "zebra"])
  }

  // MARK: - findGitDir

  @Test("finds .git directory")
  func findGitDirDirectory() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createGitDir(at: tmp)

    let result = gitService.findGitDir(from: tmp)
    #expect(result == (tmp as NSString).appendingPathComponent(".git"))
  }

  @Test("follows .git file (worktree) to gitdir pointer")
  func findGitDirWorktreeFile() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    // Main repo
    let mainGitDir = (tmp as NSString).appendingPathComponent("main/.git")
    try FileManager.default.createDirectory(atPath: mainGitDir, withIntermediateDirectories: true)

    // Worktree with .git file
    let worktree = (tmp as NSString).appendingPathComponent("worktree")
    try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
    let worktreeGitDir = "\(mainGitDir)/worktrees/feature"
    try FileManager.default.createDirectory(atPath: worktreeGitDir, withIntermediateDirectories: true)
    try "gitdir: \(worktreeGitDir)".write(
      toFile: (worktree as NSString).appendingPathComponent(".git"),
      atomically: true, encoding: .utf8
    )

    let result = gitService.findGitDir(from: worktree)
    #expect(result == worktreeGitDir)
  }

  @Test("returns nil when no .git exists")
  func findGitDirNone() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    #expect(gitService.findGitDir(from: tmp) == nil)
  }

  // MARK: - worktreeBranches

  @Test("lists branches checked out in worktrees")
  func worktreeBranchesFromWorktreeHeads() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createGitDir(at: tmp, branch: "main")
    let gitDir = (tmp as NSString).appendingPathComponent(".git")

    // Create worktree HEAD files
    let wt1Dir = (gitDir as NSString).appendingPathComponent("worktrees/wt1")
    try FileManager.default.createDirectory(atPath: wt1Dir, withIntermediateDirectories: true)
    try "ref: refs/heads/feature-a".write(
      toFile: (wt1Dir as NSString).appendingPathComponent("HEAD"),
      atomically: true, encoding: .utf8
    )

    let wt2Dir = (gitDir as NSString).appendingPathComponent("worktrees/wt2")
    try FileManager.default.createDirectory(atPath: wt2Dir, withIntermediateDirectories: true)
    try "ref: refs/heads/feature-b".write(
      toFile: (wt2Dir as NSString).appendingPathComponent("HEAD"),
      atomically: true, encoding: .utf8
    )

    let branches = gitService.worktreeBranches(at: tmp)
    #expect(branches == ["feature-a", "feature-b"])
  }

  @Test("returns empty when no worktrees directory")
  func worktreeBranchesEmpty() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createGitDir(at: tmp)

    #expect(gitService.worktreeBranches(at: tmp) == [])
  }

  // MARK: - checkoutBranch

  @Test("checks out an existing branch successfully")
  func checkoutBranchSuccess() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try gitService.initGitRepo(at: tmp)
    try gitService.createBranch(repoPath: tmp, newBranch: "feature", baseBranch: "main")

    // Switch back to main first
    _ = gitService.checkoutBranch("main", at: tmp)
    #expect(gitService.currentBranch(at: tmp) == "main")

    // Now checkout feature
    let error = gitService.checkoutBranch("feature", at: tmp)
    #expect(error == nil)
    #expect(gitService.currentBranch(at: tmp) == "feature")
  }

  @Test("returns error for nonexistent branch")
  func checkoutBranchNonexistent() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try gitService.initGitRepo(at: tmp)

    let error = gitService.checkoutBranch("nonexistent", at: tmp)
    #expect(error != nil)
  }
}
