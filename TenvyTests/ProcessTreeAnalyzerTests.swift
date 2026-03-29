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
import Testing
@testable import Tenvy

/// Tests for `ProcessTreeAnalyzer.findClaudeProcess` — the pure function that
/// locates a claude process in a `ProcessPoller` snapshot using ancestry and
/// argument matching.
struct ProcessTreeAnalyzerTests {

  // MARK: - Helpers

  /// Build a `ProcessRecord` for use in test snapshots.
  private func record(pid: pid_t, ppid: pid_t, args: String) -> ProcessPoller.ProcessRecord {
    ProcessPoller.ProcessRecord(pid: pid, ppid: ppid, cpu: 0, memoryKB: 0, args: args)
  }

  /// Build a snapshot dictionary from an array of records.
  private func snapshot(_ records: [ProcessPoller.ProcessRecord]) -> [pid_t: ProcessPoller.ProcessRecord] {
    Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0) })
  }

  // MARK: - Basic matching

  @Test("finds claude process that is a direct child of the shell")
  func findDirectChild() {
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: 100, ppid: 1, args: "/bin/zsh"),
      record(pid: 200, ppid: 100, args: "/usr/local/bin/claude --resume abc123"),
    ])

    let result = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: "abc123")
    #expect(result == 200)
  }

  @Test("returns shellPID directly when it is itself a claude process")
  func shellIsClaudeProcess() {
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: 100, ppid: 1, args: "/usr/local/bin/claude --resume abc123"),
    ])

    let result = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: "abc123")
    #expect(result == 100)
  }

  @Test("returns 0 when no claude process exists")
  func noClaudeProcess() {
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: 100, ppid: 1, args: "/bin/zsh"),
      record(pid: 200, ppid: 100, args: "/usr/bin/vim"),
    ])

    let result = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: nil)
    #expect(result == 0)
  }

  // MARK: - Session ID matching

  @Test("matches only the claude process with the correct session ID")
  func sessionIdFiltering() {
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: 100, ppid: 1, args: "/bin/zsh"),
      record(pid: 200, ppid: 100, args: "/usr/local/bin/claude --resume session-A"),
      record(pid: 300, ppid: 100, args: "/usr/local/bin/claude --resume session-B"),
    ])

    let resultA = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: "session-A")
    #expect(resultA == 200)

    let resultB = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: "session-B")
    #expect(resultB == 300)
  }

  @Test("nil sessionId matches any claude process")
  func nilSessionIdMatchesAny() {
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: 100, ppid: 1, args: "/bin/zsh"),
      record(pid: 200, ppid: 100, args: "/usr/local/bin/claude --resume session-A"),
    ])

    let result = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: nil)
    #expect(result == 200)
  }

  // MARK: - Multi-session disambiguation (the bug scenario)

  @Test("with foreground PID, each session gets its own claude process")
  func multiSessionWithForegroundPID() {
    // Simulates two sessions in the same folder, each with its own PTY.
    // Ghostty's foreground_pid gives us the exact PID for each surface.
    let appPID: pid_t = 50
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: appPID, ppid: 1, args: "Tenvy.app"),
      // Session A: PTY foreground = claude PID 200
      record(pid: 200, ppid: appPID, args: "/usr/local/bin/claude --resume session-A"),
      // Session B: PTY foreground = claude PID 300
      record(pid: 300, ppid: appPID, args: "/usr/local/bin/claude --resume session-B"),
    ])

    // When we pass the exact foreground PID as shellPID, it matches directly
    // via candidates.contains(shellPID) — no ancestry walk needed.
    let resultA = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 200, sessionId: nil)
    #expect(resultA == 200)

    let resultB = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 300, sessionId: nil)
    #expect(resultB == 300)
  }

  @Test("with shellPID 0, falls back to app PID ancestry and finds a claude process")
  func fallbackToAppPIDAncestry() {
    // When foregroundPid is unavailable (0), the analyzer uses the app's own PID
    // as the ancestor. This still works for single-session scenarios.
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: pid_t(ProcessInfo.processInfo.processIdentifier), ppid: 1, args: "Tenvy.app"),
      record(pid: 500, ppid: pid_t(ProcessInfo.processInfo.processIdentifier), args: "/usr/local/bin/claude"),
    ])

    let result = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 0, sessionId: nil)
    #expect(result == 500)
  }

  // MARK: - Ancestry

  @Test("finds claude process through deep ancestry chain")
  func deepAncestry() {
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: 100, ppid: 1, args: "/bin/zsh"),
      record(pid: 200, ppid: 100, args: "/bin/bash"),
      record(pid: 300, ppid: 200, args: "/usr/bin/env node"),
      record(pid: 400, ppid: 300, args: "/usr/local/bin/claude"),
    ])

    let result = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: nil)
    #expect(result == 400)
  }

  @Test("does not match claude process under a different ancestor")
  func differentAncestor() {
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: 100, ppid: 1, args: "/bin/zsh"),         // our shell
      record(pid: 200, ppid: 1, args: "/bin/zsh"),         // another shell
      record(pid: 300, ppid: 200, args: "/usr/local/bin/claude"),  // under different shell
    ])

    let result = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: nil)
    #expect(result == 0)
  }

  // MARK: - Edge cases

  @Test("handles empty snapshot")
  func emptySnapshot() {
    let result = ProcessTreeAnalyzer.findClaudeProcess(in: [:], shellPID: 100, sessionId: nil)
    #expect(result == 0)
  }

  @Test("handles snapshot with no matching args")
  func noMatchingArgs() {
    let snap = snapshot([
      record(pid: 100, ppid: 1, args: "/bin/zsh"),
      record(pid: 200, ppid: 100, args: "/usr/bin/python3 script.py"),
    ])

    let result = ProcessTreeAnalyzer.findClaudeProcess(in: snap, shellPID: 100, sessionId: nil)
    #expect(result == 0)
  }
}
