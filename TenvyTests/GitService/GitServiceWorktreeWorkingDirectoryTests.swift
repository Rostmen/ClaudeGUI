// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

struct GitServiceWorktreeWorkingDirectoryTests {

  @Test("returns worktreePath when project is at git root")
  func projectAtGitRoot() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/worktrees/session-a",
      gitRoot: "/repo",
      projectPath: "/repo"
    )
    #expect(result == "/worktrees/session-a")
  }

  @Test("preserves subfolder when project is in a subdirectory of git root")
  func projectInSubfolder() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/worktrees/session-a",
      gitRoot: "/repo",
      projectPath: "/repo/ios"
    )
    #expect(result == "/worktrees/session-a/ios")
  }

  @Test("preserves deep subfolder offset")
  func deepSubfolder() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/worktrees/session-b",
      gitRoot: "/repo",
      projectPath: "/repo/packages/frontend/src"
    )
    #expect(result == "/worktrees/session-b/packages/frontend/src")
  }

  @Test("worktree-to-worktree split preserves project subfolder")
  func worktreeToWorktreeSplit() {
    // Source is a worktree, but projectPath stays as the original project path.
    // gitRoot is always the main repo root.
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/worktrees/session-b",
      gitRoot: "/repo",
      projectPath: "/repo/ios"
    )
    #expect(result == "/worktrees/session-b/ios")
  }

  @Test("returns worktreePath when project path is outside git root")
  func projectOutsideGitRoot() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/worktrees/session-a",
      gitRoot: "/repo",
      projectPath: "/completely/different/path"
    )
    #expect(result == "/worktrees/session-a")
  }

  @Test("handles path normalization")
  func pathNormalization() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/worktrees/session-a",
      gitRoot: "/repo/",
      projectPath: "/repo/src"
    )
    #expect(result == "/worktrees/session-a/src")
  }

  @Test("works with custom worktree location")
  func customWorktreeLocation() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/Users/dev/worktrees/MyApp-abc123/feature-x",
      gitRoot: "/Users/dev/Projects/MyApp",
      projectPath: "/Users/dev/Projects/MyApp/packages/ios"
    )
    #expect(result == "/Users/dev/worktrees/MyApp-abc123/feature-x/packages/ios")
  }
}
