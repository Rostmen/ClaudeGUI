// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

struct GitServiceWorktreeWorkingDirectoryTests {

  @Test("returns worktreePath when source equals project path")
  func sourceEqualsProjectPath() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/new/worktree",
      sourceProjectPath: "/repo",
      sourceWorkingDirectory: "/repo"
    )
    #expect(result == "/new/worktree")
  }

  @Test("preserves subfolder offset from regular project")
  func subfolderFromRegularProject() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/new/worktree",
      sourceProjectPath: "/repo",
      sourceWorkingDirectory: "/repo/src/ios"
    )
    #expect(result == "/new/worktree/src/ios")
  }

  @Test("preserves deep subfolder offset")
  func deepSubfolder() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/worktrees/session-b",
      sourceProjectPath: "/repo",
      sourceWorkingDirectory: "/repo/packages/frontend/src/components"
    )
    #expect(result == "/worktrees/session-b/packages/frontend/src/components")
  }

  @Test("preserves subfolder offset when splitting from default-location worktree")
  func subfolderFromDefaultWorktree() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/repo/.claude/worktrees/session-b",
      sourceProjectPath: "/repo/.claude/worktrees/session-a",
      sourceWorkingDirectory: "/repo/.claude/worktrees/session-a/src/ios"
    )
    #expect(result == "/repo/.claude/worktrees/session-b/src/ios")
  }

  @Test("preserves subfolder offset when splitting from custom-location worktree")
  func subfolderFromCustomWorktree() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/Users/dev/worktrees/session-b",
      sourceProjectPath: "/Users/dev/worktrees/session-a",
      sourceWorkingDirectory: "/Users/dev/worktrees/session-a/src/ios"
    )
    #expect(result == "/Users/dev/worktrees/session-b/src/ios")
  }

  @Test("returns worktreePath when source is at worktree root")
  func sourceAtWorktreeRoot() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/worktrees/session-b",
      sourceProjectPath: "/worktrees/session-a",
      sourceWorkingDirectory: "/worktrees/session-a"
    )
    #expect(result == "/worktrees/session-b")
  }

  @Test("returns worktreePath when source is outside project path")
  func sourceOutsideProjectPath() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/new/worktree",
      sourceProjectPath: "/repo",
      sourceWorkingDirectory: "/completely/different/path"
    )
    #expect(result == "/new/worktree")
  }

  @Test("handles path normalization with trailing slashes")
  func pathNormalization() {
    let result = GitService.worktreeWorkingDirectory(
      worktreePath: "/new/worktree",
      sourceProjectPath: "/repo/",
      sourceWorkingDirectory: "/repo/src"
    )
    #expect(result == "/new/worktree/src")
  }
}
