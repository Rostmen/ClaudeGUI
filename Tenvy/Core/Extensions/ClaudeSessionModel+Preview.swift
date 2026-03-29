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

#if DEBUG

import Foundation

// MARK: - Preview Helpers

extension ClaudeSessionModel {

  /// Creates a preview model with customizable state.
  @MainActor
  static func preview(
    title: String = "Implement feature",
    workingDirectory: String = "/Users/dev/Projects/MyApp",
    lastModified: Date = Date(),
    isActive: Bool = false,
    hookState: HookState? = nil,
    cpu: Double = 0,
    memory: UInt64 = 0,
    pid: pid_t = 0,
    currentTool: String? = nil,
    gitBranch: String? = nil
  ) -> ClaudeSessionModel {
    let session = ClaudeSession(
      id: UUID().uuidString,
      title: title,
      projectPath: workingDirectory,
      workingDirectory: workingDirectory,
      lastModified: lastModified,
      filePath: nil
    )
    let runtime = SessionRuntimeInfo()
    if isActive {
      runtime.state = .waitingForInput
      runtime.pid = pid > 0 ? pid : 12345
      runtime.cpu = cpu
      runtime.memory = memory
      runtime.hookState = hookState
      runtime.currentTool = currentTool
    }
    runtime.gitBranch = gitBranch
    return ClaudeSessionModel(session: session, runtime: runtime)
  }
}

// MARK: - Preset Variants

extension ClaudeSessionModel {

  /// Inactive session (gray dot, no process info)
  @MainActor
  static var previewInactive: ClaudeSessionModel {
    .preview(title: "Fix login bug", workingDirectory: "/Users/dev/Projects/AuthService")
  }

  /// Inactive session with git branch
  @MainActor
  static var previewInactiveWithBranch: ClaudeSessionModel {
    .preview(
      title: "Fix login bug",
      workingDirectory: "/Users/dev/Projects/AuthService",
      gitBranch: "fix/auth-token-refresh"
    )
  }

  /// Active session — Claude is thinking (yellow dot)
  @MainActor
  static var previewThinking: ClaudeSessionModel {
    .preview(
      title: "Refactor database layer",
      workingDirectory: "/Users/dev/Projects/Backend",
      isActive: true,
      hookState: .thinking,
      cpu: 45.2,
      memory: 256 * 1024 * 1024,
      pid: 48201,
      currentTool: "Edit",
      gitBranch: "refactor/db-layer"
    )
  }

  /// Active session — running a Bash command
  @MainActor
  static var previewRunningBash: ClaudeSessionModel {
    .preview(
      title: "Setup CI pipeline",
      workingDirectory: "/Users/dev/Projects/Infra",
      isActive: true,
      hookState: .thinking,
      cpu: 12.8,
      memory: 180 * 1024 * 1024,
      pid: 51003,
      currentTool: "Bash",
      gitBranch: "main"
    )
  }

  /// Active session — waiting for user input (green blinking dot)
  @MainActor
  static var previewWaiting: ClaudeSessionModel {
    .preview(
      title: "Add unit tests",
      workingDirectory: "/Users/dev/Projects/MyApp",
      isActive: true,
      hookState: .waiting,
      cpu: 1.2,
      memory: 210 * 1024 * 1024,
      pid: 33120,
      gitBranch: "feat/unit-tests"
    )
  }

  /// Active session — waiting for permission (red blinking dot)
  @MainActor
  static var previewWaitingPermission: ClaudeSessionModel {
    .preview(
      title: "Deploy to staging",
      workingDirectory: "/Users/dev/Projects/Deploy",
      isActive: true,
      hookState: .waitingPermission,
      cpu: 0.5,
      memory: 195 * 1024 * 1024,
      pid: 29874,
      gitBranch: "release/v2.1.0"
    )
  }

  /// Active session — processing (yellow dot, user just sent a message)
  @MainActor
  static var previewProcessing: ClaudeSessionModel {
    .preview(
      title: "Code review",
      workingDirectory: "/Users/dev/Projects/Frontend",
      isActive: true,
      hookState: .processing,
      cpu: 30.0,
      memory: 240 * 1024 * 1024,
      pid: 44512
    )
  }

  /// Active session — just started (blue dot)
  @MainActor
  static var previewStarted: ClaudeSessionModel {
    .preview(
      title: "New Session",
      workingDirectory: "/Users/dev/Projects/NewProject",
      isActive: true,
      hookState: .started,
      pid: 50001,
      gitBranch: "main"
    )
  }

  /// Inactive session — no git repo
  @MainActor
  static var previewNoGit: ClaudeSessionModel {
    .preview(
      title: "Explore docs",
      workingDirectory: "/Users/dev/Documents/notes"
    )
  }
}

#endif
