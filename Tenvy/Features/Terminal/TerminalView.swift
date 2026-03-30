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

// MARK: - Split Direction

/// Direction in which a new split pane should appear.
enum SplitDirection {
  case right, down, left, up
  var isVertical: Bool { self == .down || self == .up }
  var isReversed: Bool { self == .left || self == .up }
}

// MARK: - Session Monitor Info

/// Holds monitoring info: state, CPU usage, memory, and the monitored PID
struct SessionMonitorInfo {
  let state: SessionState
  let cpu: Double
  let memory: UInt64
  let pid: pid_t
}

// MARK: - Session State Monitor
// Based on https://github.com/Aura-Technologies-llc/ClaudeCodeMonitor

/// Monitors the CPU/memory of a single session's process group.
///
/// Instead of running its own `ps` subprocess, it subscribes to the shared
/// `ProcessPoller` actor, which runs one `ps` per 500 ms for all sessions combined.
///
/// PID discovery uses a `pidProvider` closure that returns the `login` process PID
/// from Ghostty's PTY. This is the root of the session's process group — it's
/// stable for the entire session lifetime. CPU and memory are summed across all
/// descendants of `login` (e.g. claude + any tools/MCP servers it spawns).
class SessionStateMonitor {
  var onStateChange: ((SessionMonitorInfo) -> Void)?

  private let pidProvider: () -> pid_t
  private let pollerId = UUID()
  private var currentState: SessionState = .inactive
  private var cpuHistory: [Double] = []
  private var stateStartTime: Date = Date()
  private let processStartTime: Date = Date()
  /// The `login` process PID — root of the session's process group.
  private(set) var lockedPID: pid_t = 0

  // Thresholds based on ClaudeCodeMonitor
  private let cpuHighThreshold: Double = 25.0  // CPU > 25% = thinking
  private let cpuLowThreshold: Double = 3.0    // CPU < 3% = idle/waiting
  private let historySize = 3                   // Rolling average window
  private let minRunningTime: TimeInterval = 5  // Min time before state changes
  private let minStateTime: TimeInterval = 2    // Min time in state before transition

  init(pidProvider: @escaping () -> pid_t) {
    self.pidProvider = pidProvider
  }

  func start() {
    let monitorId = pollerId
    Task {
      await ProcessPoller.shared.subscribe(id: monitorId) { [weak self] snapshot in
        self?.handleSnapshot(snapshot)
      }
    }
    emit(.waitingForInput, cpu: 0, memory: 0)
  }

  func stop() {
    let monitorId = pollerId
    Task { await ProcessPoller.shared.unsubscribe(id: monitorId) }
  }

  private func handleSnapshot(_ snapshot: [pid_t: ProcessPoller.ProcessRecord]) {
    // Lock onto the login PID from the provider. It's the root of the process
    // group and stays alive for the entire session.
    if lockedPID == 0 || snapshot[lockedPID] == nil {
      let providerPid = pidProvider()
      if providerPid > 0, snapshot[providerPid] != nil {
        lockedPID = providerPid
      } else {
        if lockedPID > 0 {
          // Had a PID but it's gone — process group exited
          emit(.inactive, cpu: 0, memory: 0)
        }
        return
      }
    }

    // Sum CPU and memory across all descendants of the locked PID
    let (totalCPU, totalMemoryKB) = Self.sumProcessGroup(root: lockedPID, in: snapshot)
    let memoryBytes = totalMemoryKB * 1024

    cpuHistory.append(totalCPU)
    if cpuHistory.count > historySize { cpuHistory.removeFirst() }

    let avgCPU = cpuHistory.reduce(0, +) / Double(cpuHistory.count)
    let timeSinceStart = Date().timeIntervalSince(processStartTime)
    let timeSinceStateChange = Date().timeIntervalSince(stateStartTime)
    let newState = deriveState(avgCPU: avgCPU, timeSinceStart: timeSinceStart, timeSinceStateChange: timeSinceStateChange)

    if newState != currentState {
      emit(newState, cpu: avgCPU, memory: memoryBytes)
    } else {
      reportStats(cpu: avgCPU, memory: memoryBytes)
    }
  }

  private func deriveState(avgCPU: Double, timeSinceStart: TimeInterval, timeSinceStateChange: TimeInterval) -> SessionState {
    switch currentState {
    case .inactive, .waitingForInput:
      if avgCPU > cpuHighThreshold && timeSinceStart > minRunningTime { return .thinking }
      return .waitingForInput
    case .thinking:
      if avgCPU < cpuLowThreshold && timeSinceStateChange > minStateTime { return .waitingForInput }
      return .thinking
    }
  }

  private func emit(_ state: SessionState, cpu: Double, memory: UInt64) {
    currentState = state
    stateStartTime = Date()
    let cb = onStateChange
    let pid = lockedPID
    DispatchQueue.main.async { cb?(SessionMonitorInfo(state: state, cpu: cpu, memory: memory, pid: pid)) }
  }

  /// Sums CPU% and memory (KB) for the root PID and all its descendants.
  /// Uses BFS to collect all processes in the group.
  static func sumProcessGroup(
    root: pid_t,
    in snapshot: [pid_t: ProcessPoller.ProcessRecord]
  ) -> (cpu: Double, memoryKB: UInt64) {
    guard let rootRecord = snapshot[root] else { return (0, 0) }

    var totalCPU = rootRecord.cpu
    var totalMemKB = rootRecord.memoryKB
    var queue: [pid_t] = [root]
    var visited: Set<pid_t> = [root]

    while !queue.isEmpty {
      let current = queue.removeFirst()
      for record in snapshot.values where record.ppid == current {
        guard visited.insert(record.pid).inserted else { continue }
        totalCPU += record.cpu
        totalMemKB += record.memoryKB
        queue.append(record.pid)
      }
    }

    return (totalCPU, totalMemKB)
  }

  /// Test-only entry point: feeds a snapshot directly without going through ProcessPoller.
  func testHandleSnapshot(_ snapshot: [pid_t: ProcessPoller.ProcessRecord]) {
    handleSnapshot(snapshot)
  }

  private func reportStats(cpu: Double, memory: UInt64) {
    let state = currentState
    let cb = onStateChange
    let pid = lockedPID
    DispatchQueue.main.async { cb?(SessionMonitorInfo(state: state, cpu: cpu, memory: memory, pid: pid)) }
  }
}
