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

/// A single handle for a Claude Code session, combining immutable session data with live
/// runtime state. Views bind to this object — they observe `runtime` properties directly
/// through the underlying `SessionRuntimeInfo` @Observable instance.
///
/// **Design note:** `ClaudeSession` (value type) and `SessionRuntimeInfo` (reference type)
/// are intentionally kept as separate storage. The split is load-bearing:
/// - `ClaudeSession` as a struct gives SwiftUI list diffing and NavigationSplitView
///   selection clean value-equality semantics.
/// - `SessionRuntimeInfo` as its own `@Observable` class ensures only the row whose
///   CPU/hookState changed re-renders, not the entire list.
///
/// `ClaudeSessionModel` is a thin facade that lets call sites work with one object
/// instead of threading both types everywhere.
@Observable
@MainActor
final class ClaudeSessionModel: Identifiable {

  // MARK: - Underlying storage

  /// The immutable session facts (title, paths, last-modified).
  /// Use `updateSession(_:)` to replace it during the temp-to-real session ID sync.
  private(set) var session: ClaudeSession

  /// The live runtime state for this session.
  /// Accessing any property of `runtime` in a view body registers fine-grained
  /// observation — changes to `runtime.cpu` will NOT re-render a row that only
  /// reads `runtime.hookState`.
  let runtime: SessionRuntimeInfo

  // MARK: - Identifiable

  /// Stable identifier for SwiftUI — uses `terminalId` so list selection and view
  /// identity survive the temp-to-real session ID sync (the ID that changes is
  /// `session.id`; `terminalId` is invariant across the sync).
  var id: String { session.terminalId }

  // MARK: - Forwarded session properties

  var sessionId: String { session.id }
  var title: String { session.title }
  var projectPath: String { session.projectPath }
  var workingDirectory: String { session.workingDirectory }
  var displayPath: String { session.displayPath }
  var lastModified: Date { session.lastModified }
  var filePath: URL? { session.filePath }
  var isNewSession: Bool { session.isNewSession }

  // MARK: - Forwarded runtime properties

  var state: SessionState { runtime.state }
  var cpu: Double { runtime.cpu }
  var memory: UInt64 { runtime.memory }
  var pid: pid_t { runtime.pid }
  var shellPid: pid_t { runtime.shellPid }
  var hookState: HookState? { runtime.hookState }
  var currentTool: String? { runtime.currentTool }
  var hasUserInteracted: Bool { runtime.hasUserInteracted }

  // MARK: - Init

  init(session: ClaudeSession, runtime: SessionRuntimeInfo) {
    self.session = session
    self.runtime = runtime
  }

  // MARK: - Session sync

  /// Replace the underlying `ClaudeSession` value.
  /// Called during the temp-to-real ID sync when Claude creates the actual JSONL file.
  /// The `terminalId` (and therefore this object's `id`) stays the same, so SwiftUI
  /// does not recreate any views that hold a reference to this model.
  func updateSession(_ newSession: ClaudeSession) {
    session = newSession
  }
}
