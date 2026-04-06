// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

/// Tests for git subprocess operations (initGitRepo, createBranch, createWorktree, removeWorktree).
/// These create real temporary git repos.
struct GitServiceGitOpsTests {

  private func makeGitService() -> GitService {
    GitService(settings: TestAppSettings.make())
  }

  private func makeTempDir() throws -> String {
    let path = NSTemporaryDirectory() + "GitServiceGitOps-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  /// Creates a real git repo at path via gitService.initGitRepo.
  private func createRealRepo(at path: String, using gitService: GitService) throws {
    try gitService.initGitRepo(at: path)
  }

  // MARK: - initGitRepo

  @Test("initializes a git repo with .git directory and initial commit")
  func initCreatesRepo() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    try gitService.initGitRepo(at: tmp)

    let gitDir = (tmp as NSString).appendingPathComponent(".git")
    var isDir: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: gitDir, isDirectory: &isDir))
    #expect(isDir.boolValue)
  }

  // MARK: - createBranch

  @Test("creates and checks out a new branch")
  func createBranchWorks() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createRealRepo(at: tmp, using: gitService)

    try gitService.createBranch(repoPath: tmp, newBranch: "feature-x", baseBranch: "main")

    #expect(gitService.currentBranch(at: tmp) == "feature-x")
  }

  @Test("throws on duplicate branch name")
  func createBranchDuplicate() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createRealRepo(at: tmp, using: gitService)

    #expect(throws: GitService.GitError.self) {
      try gitService.createBranch(repoPath: tmp, newBranch: "main", baseBranch: "main")
    }
  }

  // MARK: - createWorktree

  @Test("creates a worktree with a new branch")
  func createWorktreeWorks() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createRealRepo(at: tmp, using: gitService)

    let worktreePath = (tmp as NSString).appendingPathComponent("worktrees/feature")
    try gitService.createWorktree(
      repoPath: tmp,
      newBranch: "feature",
      baseBranch: "main",
      destinationPath: worktreePath,
      initSubmodules: false,
      symlinkBuildArtifacts: false
    )

    #expect(FileManager.default.fileExists(atPath: worktreePath))
    // Worktree has a .git file (not directory)
    let gitFile = (worktreePath as NSString).appendingPathComponent(".git")
    var isDir: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: gitFile, isDirectory: &isDir))
    #expect(!isDir.boolValue)
  }

  @Test("throws when destination already exists")
  func createWorktreeDestinationExists() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createRealRepo(at: tmp, using: gitService)

    let worktreePath = (tmp as NSString).appendingPathComponent("existing")
    try FileManager.default.createDirectory(atPath: worktreePath, withIntermediateDirectories: true)

    #expect(throws: GitService.GitError.self) {
      try gitService.createWorktree(
        repoPath: tmp,
        newBranch: "feat",
        baseBranch: "main",
        destinationPath: worktreePath,
        initSubmodules: false,
        symlinkBuildArtifacts: false
      )
    }
  }

  // MARK: - removeWorktree

  @Test("removes a worktree")
  func removeWorktreeWorks() throws {
    let gitService = makeGitService()
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }
    try createRealRepo(at: tmp, using: gitService)

    let worktreePath = (tmp as NSString).appendingPathComponent("worktrees/to-remove")
    try gitService.createWorktree(
      repoPath: tmp,
      newBranch: "to-remove",
      baseBranch: "main",
      destinationPath: worktreePath,
      initSubmodules: false,
      symlinkBuildArtifacts: false
    )
    #expect(FileManager.default.fileExists(atPath: worktreePath))

    try gitService.removeWorktree(repoPath: tmp, worktreePath: worktreePath)

    #expect(!FileManager.default.fileExists(atPath: worktreePath))
  }

  // MARK: - GitError descriptions

  @Test("error descriptions are non-empty")
  func errorDescriptions() {
    let errors: [GitService.GitError] = [
      .gitNotFound,
      .worktreeCreationFailed("msg"),
      .gitInitFailed("msg"),
      .branchCreationFailed("msg"),
      .destinationAlreadyExists("/path"),
    ]
    for error in errors {
      #expect(error.errorDescription != nil)
      #expect(!error.errorDescription!.isEmpty)
    }
  }
}
