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

import Dependencies
import Foundation

// MARK: - HookEventsFilePath

/// The URL of the JSONL file written by Claude Code hooks.
/// Override in tests to redirect to a temp file.
private struct HookEventsFilePathKey: DependencyKey {
  static let liveValue: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/chat-sessions-events.jsonl")

  // Each test gets a unique temp path so parallel tests don't share state.
  static var testValue: URL {
    URL.temporaryDirectory
      .appendingPathComponent("tenvy-test-hook-events-\(UUID().uuidString).jsonl")
  }
}

extension DependencyValues {
  /// Path to the hook events JSONL file. Swap in tests to use a temp file.
  var hookEventsFilePath: URL {
    get { self[HookEventsFilePathKey.self] }
    set { self[HookEventsFilePathKey.self] = newValue }
  }

  /// Git service for worktree, branch, and repo operations.
  var gitService: GitService {
    get { self[GitServiceKey.self] }
    set { self[GitServiceKey.self] = newValue }
  }
}

// MARK: - GitService

private struct GitServiceKey: DependencyKey {
  static let liveValue = GitService(settings: AppSettings.shared)
  static let testValue = GitService(settings: AppSettings.shared)
}

