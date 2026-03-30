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

/// Tests for `SessionStateMonitor` — verifies PID locking on the login process
/// and CPU/memory aggregation across the entire process group.
struct SessionStateMonitorTests {

  // MARK: - Helpers

  private func record(pid: pid_t, ppid: pid_t, args: String, cpu: Double = 0, memoryKB: UInt64 = 1024) -> ProcessPoller.ProcessRecord {
    ProcessPoller.ProcessRecord(pid: pid, ppid: ppid, cpu: cpu, memoryKB: memoryKB, args: args)
  }

  private func snapshot(_ records: [ProcessPoller.ProcessRecord]) -> [pid_t: ProcessPoller.ProcessRecord] {
    Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0) })
  }

  // MARK: - sumProcessGroup

  @Test("sums CPU and memory across login → claude → child processes")
  func sumProcessGroupTree() {
    let snap = snapshot([
      record(pid: 100, ppid: 1, args: "/usr/bin/login", cpu: 1.0, memoryKB: 100),
      record(pid: 200, ppid: 100, args: "/usr/local/bin/claude", cpu: 15.0, memoryKB: 50_000),
      record(pid: 300, ppid: 200, args: "node mcp-server.js", cpu: 8.0, memoryKB: 30_000),
      record(pid: 400, ppid: 200, args: "npm exec xcodebuildmcp", cpu: 5.0, memoryKB: 20_000),
    ])

    let (cpu, mem) = SessionStateMonitor.sumProcessGroup(root: 100, in: snap)
    #expect(cpu == 29.0)
    #expect(mem == 100_100)
  }

  @Test("sums only the root when it has no children")
  func sumProcessGroupSingleProcess() {
    let snap = snapshot([
      record(pid: 100, ppid: 1, args: "/usr/bin/login", cpu: 1.0, memoryKB: 500),
    ])

    let (cpu, mem) = SessionStateMonitor.sumProcessGroup(root: 100, in: snap)
    #expect(cpu == 1.0)
    #expect(mem == 500)
  }

  @Test("does not include unrelated processes")
  func sumProcessGroupExcludesUnrelated() {
    let snap = snapshot([
      record(pid: 100, ppid: 1, args: "/usr/bin/login", cpu: 0.1, memoryKB: 100),
      record(pid: 200, ppid: 100, args: "/usr/local/bin/claude", cpu: 10.0, memoryKB: 50_000),
      // Different login group — should not be included
      record(pid: 500, ppid: 1, args: "/usr/bin/login", cpu: 20.0, memoryKB: 80_000),
      record(pid: 600, ppid: 500, args: "/usr/local/bin/claude", cpu: 30.0, memoryKB: 90_000),
    ])

    let (cpu, mem) = SessionStateMonitor.sumProcessGroup(root: 100, in: snap)
    #expect(cpu == 10.1)
    #expect(mem == 50_100)
  }

  @Test("returns zero for unknown root PID")
  func sumProcessGroupUnknownRoot() {
    let (cpu, mem) = SessionStateMonitor.sumProcessGroup(root: 999, in: [:])
    #expect(cpu == 0)
    #expect(mem == 0)
  }

  // MARK: - PID locking

  @Test("locks onto the provider PID directly (login)")
  func locksOntoProviderPID() {
    let monitor = SessionStateMonitor(pidProvider: { 100 })

    let snap = snapshot([
      record(pid: 100, ppid: 1, args: "/usr/bin/login"),
      record(pid: 200, ppid: 100, args: "/usr/local/bin/claude"),
    ])

    monitor.testHandleSnapshot(snap)
    #expect(monitor.lockedPID == 100, "Should lock onto login PID, not walk to leaf")
  }

  @Test("lockedPID stays locked even when pidProvider returns different value")
  func pidLockedIn() {
    var providerPID: pid_t = 100
    let monitor = SessionStateMonitor(pidProvider: { providerPID })

    let snap = snapshot([
      record(pid: 100, ppid: 1, args: "/usr/bin/login"),
      record(pid: 200, ppid: 100, args: "/usr/local/bin/claude"),
      record(pid: 300, ppid: 1, args: "/usr/bin/login"),
      record(pid: 400, ppid: 300, args: "/usr/local/bin/claude"),
    ])

    monitor.testHandleSnapshot(snap)
    #expect(monitor.lockedPID == 100)

    providerPID = 300
    for _ in 0..<10 {
      monitor.testHandleSnapshot(snap)
      #expect(monitor.lockedPID == 100, "PID should not flip between polls")
    }
  }

  @Test("re-discovers via provider when locked PID dies")
  func pidReDiscoveryWhenProcessDies() {
    var providerPID: pid_t = 100
    let monitor = SessionStateMonitor(pidProvider: { providerPID })

    let snap1 = snapshot([
      record(pid: 100, ppid: 1, args: "/usr/bin/login"),
      record(pid: 200, ppid: 100, args: "/usr/local/bin/claude"),
    ])
    monitor.testHandleSnapshot(snap1)
    #expect(monitor.lockedPID == 100)

    providerPID = 300
    let snap2 = snapshot([
      record(pid: 300, ppid: 1, args: "/usr/bin/login"),
      record(pid: 400, ppid: 300, args: "/usr/local/bin/claude"),
    ])
    monitor.testHandleSnapshot(snap2)
    #expect(monitor.lockedPID == 300)
  }

  @Test("does not lock when pidProvider returns 0")
  func noPIDWhenProviderReturnsZero() {
    let monitor = SessionStateMonitor(pidProvider: { 0 })

    let snap = snapshot([
      record(pid: 200, ppid: 1, args: "/usr/local/bin/claude"),
    ])

    monitor.testHandleSnapshot(snap)
    #expect(monitor.lockedPID == 0)
  }

  @Test("does not lock when provider PID is not in snapshot")
  func noPIDWhenNotInSnapshot() {
    let monitor = SessionStateMonitor(pidProvider: { 999 })

    let snap = snapshot([
      record(pid: 200, ppid: 1, args: "/usr/local/bin/claude"),
    ])

    monitor.testHandleSnapshot(snap)
    #expect(monitor.lockedPID == 0)
  }
}
