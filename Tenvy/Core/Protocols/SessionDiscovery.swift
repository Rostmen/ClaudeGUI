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

/// Discovers and manages Claude Code sessions on disk
@MainActor
protocol SessionDiscovery: AnyObject {
  /// All discovered sessions, sorted by last modified date descending
  var sessions: [ClaudeSession] { get }
  /// True while an async scan is in progress
  var isLoading: Bool { get }

  /// Scan ~/.claude/projects/ and refresh the sessions list
  func loadSessions() async

  /// Insert a session at the front of the list (for newly created sessions)
  func addSession(_ session: ClaudeSession)

  /// Delete a session's JSONL file from disk and remove it from the list
  func deleteSession(_ session: ClaudeSession) throws

  /// Rename a session by rewriting the summary line in the JSONL file
  func renameSession(_ session: ClaudeSession, to newTitle: String) throws
}

// MARK: - Conformance

extension SessionManager: SessionDiscovery {}
