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

/// Analyzes process tree to find Claude processes
struct ProcessTreeAnalyzer {
  /// Find Claude process using a pre-fetched `ProcessPoller` snapshot.
  /// This is the hot-path overload used during monitoring — no subprocess is spawned.
  static func findClaudeProcess(
    in snapshot: [pid_t: ProcessPoller.ProcessRecord],
    shellPID: pid_t,
    sessionId: String?
  ) -> pid_t {
    var parentMap: [pid_t: pid_t] = [:]
    var candidates: [pid_t] = []

    for record in snapshot.values {
      parentMap[record.pid] = record.ppid
      if isClaudeProcess(args: record.args, sessionId: sessionId) {
        candidates.append(record.pid)
      }
    }

    if candidates.contains(shellPID) { return shellPID }

    // shellPID == 0 means no direct shell PID handle (Ghostty manages its own PTY).
    // Fall back to the app's own PID as the ancestor: Ghostty forks inside the Tenvy
    // process, so all PTY-spawned processes are direct children of the app process.
    // This correctly excludes claude subprocesses spawned by Claude Desktop or other
    // apps that also happen to have "claude" in their args.
    let effectiveAncestor: pid_t = shellPID == 0
      ? pid_t(ProcessInfo.processInfo.processIdentifier)
      : shellPID

    for pid in candidates where isDescendant(pid: pid, of: effectiveAncestor, parentMap: parentMap) {
      return pid
    }
    return 0
  }

  /// Check if process arguments indicate a Claude process
  private static func isClaudeProcess(args: String, sessionId: String?) -> Bool {
    // Look for the claude CLI process
    guard args.contains("claude") else {
      return false
    }

    // If we have a session ID, verify it matches
    if let sessionId = sessionId, !sessionId.isEmpty {
      return args.contains(sessionId)
    }

    return true
  }

  /// Check if pid is a descendant of ancestorPID using the parent map
  private static func isDescendant(pid: pid_t, of ancestorPID: pid_t, parentMap: [pid_t: pid_t]) -> Bool {
    var current = pid
    while let parent = parentMap[current] {
      if parent == ancestorPID { return true }
      if parent <= 1 { return false }  // Reached init/launchd
      current = parent
    }
    return false
  }
}
