// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

struct GitServiceDefaultWorktreePathTests {

  @Test("uses .claude/worktrees when location is defaultClaude")
  func defaultClaudeLocation() {
    let settings = TestAppSettings.make()
    settings.worktreeLocation = .defaultClaude
    let service = GitService(settings: settings)

    let result = service.defaultWorktreePath(repoRoot: "/repo", branchName: "feature-x")
    #expect(result == "/repo/.claude/worktrees/feature-x")
  }

  @Test("uses custom root when location is custom")
  func customLocation() {
    let settings = TestAppSettings.make()
    settings.worktreeLocation = .custom
    settings.customWorktreeRoot = "/Users/dev/worktrees"
    let service = GitService(settings: settings)

    let result = service.defaultWorktreePath(repoRoot: "/repo/MyApp", branchName: "feature-x", sessionId: "abc12345-6789")
    #expect(result == "/Users/dev/worktrees/MyApp-abc12345/feature-x")
  }

  @Test("falls back to default when custom root is empty")
  func emptyCustomRootFallback() {
    let settings = TestAppSettings.make()
    settings.worktreeLocation = .custom
    settings.customWorktreeRoot = ""
    let service = GitService(settings: settings)

    let result = service.defaultWorktreePath(repoRoot: "/repo", branchName: "fix")
    #expect(result == "/repo/.claude/worktrees/fix")
  }

  @Test("sanitizes slashes in branch names")
  func sanitizesSlashes() {
    let settings = TestAppSettings.make()
    settings.worktreeLocation = .defaultClaude
    let service = GitService(settings: settings)

    let result = service.defaultWorktreePath(repoRoot: "/repo", branchName: "feature/auth/login")
    #expect(result == "/repo/.claude/worktrees/feature-auth-login")
  }
}
