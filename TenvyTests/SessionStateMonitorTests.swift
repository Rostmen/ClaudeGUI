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

/// Tests for `SessionStateMonitor.handleSnapshot` — verifies that a locked-in
/// claude PID is reused across polls instead of re-searching (which causes
/// PID flipping when multiple sessions share the same folder).
struct SessionStateMonitorTests {

  // MARK: - Helpers

  private func record(pid: pid_t, ppid: pid_t, args: String, cpu: Double = 0) -> ProcessPoller.ProcessRecord {
    ProcessPoller.ProcessRecord(pid: pid, ppid: ppid, cpu: cpu, memoryKB: 1024, args: args)
  }

  private func snapshot(_ records: [ProcessPoller.ProcessRecord]) -> [pid_t: ProcessPoller.ProcessRecord] {
    Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0) })
  }

  @Test("claudePID stays locked once found, even when multiple candidates exist")
  func pidLockedIn() {
    let appPID = pid_t(ProcessInfo.processInfo.processIdentifier)
    let monitor = SessionStateMonitor(processPID: 0, sessionId: nil)

    // Snapshot with two claude processes under the app
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: appPID, ppid: 1, args: "Tenvy.app"),
      record(pid: 200, ppid: appPID, args: "/usr/local/bin/claude"),
      record(pid: 300, ppid: appPID, args: "/usr/local/bin/claude"),
    ])

    // First poll — discover a PID
    monitor.testHandleSnapshot(snap, shellPID: 0, sessionId: nil)
    let firstPID = monitor.claudePID
    #expect(firstPID > 0)

    // Simulate 10 more polls — claudePID must not flip
    for _ in 0..<10 {
      monitor.testHandleSnapshot(snap, shellPID: 0, sessionId: nil)
      #expect(monitor.claudePID == firstPID, "PID should not flip between polls")
    }
  }

  @Test("claudePID re-searches when locked PID disappears from snapshot")
  func pidReSearchesWhenProcessDies() {
    let appPID = pid_t(ProcessInfo.processInfo.processIdentifier)
    let monitor = SessionStateMonitor(processPID: 0, sessionId: nil)

    // First snapshot: only PID 200
    let snap1 = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: appPID, ppid: 1, args: "Tenvy.app"),
      record(pid: 200, ppid: appPID, args: "/usr/local/bin/claude"),
    ])
    monitor.testHandleSnapshot(snap1, shellPID: 0, sessionId: nil)
    #expect(monitor.claudePID == 200)

    // Second snapshot: PID 200 gone, PID 300 appears
    let snap2 = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: appPID, ppid: 1, args: "Tenvy.app"),
      record(pid: 300, ppid: appPID, args: "/usr/local/bin/claude"),
    ])
    monitor.testHandleSnapshot(snap2, shellPID: 0, sessionId: nil)
    #expect(monitor.claudePID == 300, "Should find new PID when old one dies")
  }

  @Test("with foreground PID, claudePID matches the exact PTY process")
  func foregroundPIDExactMatch() {
    let appPID = pid_t(ProcessInfo.processInfo.processIdentifier)
    let monitor = SessionStateMonitor(processPID: 200, sessionId: nil)

    // Two claude processes, but shellPID=200 pinpoints the right one
    let snap = snapshot([
      record(pid: 1, ppid: 0, args: "/sbin/launchd"),
      record(pid: appPID, ppid: 1, args: "Tenvy.app"),
      record(pid: 200, ppid: appPID, args: "/usr/local/bin/claude"),
      record(pid: 300, ppid: appPID, args: "/usr/local/bin/claude"),
    ])

    monitor.testHandleSnapshot(snap, shellPID: 200, sessionId: nil)
    #expect(monitor.claudePID == 200, "Should match the exact foreground PID, not the other claude process")
  }
}
