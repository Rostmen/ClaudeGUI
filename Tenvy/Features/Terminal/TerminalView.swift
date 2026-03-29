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

/// Monitors the CPU/memory of a single session's claude process.
///
/// Instead of running its own `ps` subprocess, it subscribes to the shared
/// `ProcessPoller` actor, which runs one `ps` per 500 ms for all sessions combined.
class SessionStateMonitor {
  let shellPID: pid_t
  let sessionId: String?
  var onStateChange: ((SessionMonitorInfo) -> Void)?

  private let pollerId = UUID()
  private var currentState: SessionState = .inactive
  private var cpuHistory: [Double] = []
  private var stateStartTime: Date = Date()
  private let processStartTime: Date = Date()
  private(set) var claudePID: pid_t = 0

  // Thresholds based on ClaudeCodeMonitor
  private let cpuHighThreshold: Double = 25.0  // CPU > 25% = thinking
  private let cpuLowThreshold: Double = 3.0    // CPU < 3% = idle/waiting
  private let historySize = 3                   // Rolling average window
  private let minRunningTime: TimeInterval = 5  // Min time before state changes
  private let minStateTime: TimeInterval = 2    // Min time in state before transition

  init(processPID: pid_t, sessionId: String? = nil) {
    self.shellPID = processPID
    self.sessionId = sessionId
  }

  func start() {
    let monitorId = pollerId
    let shellPID = self.shellPID
    let sessionId = self.sessionId
    Task {
      await ProcessPoller.shared.subscribe(id: monitorId) { [weak self] snapshot in
        self?.handleSnapshot(snapshot, shellPID: shellPID, sessionId: sessionId)
      }
    }
    emit(.waitingForInput, cpu: 0, memory: 0)
  }

  func stop() {
    let monitorId = pollerId
    Task { await ProcessPoller.shared.unsubscribe(id: monitorId) }
  }

  private func handleSnapshot(_ snapshot: [pid_t: ProcessPoller.ProcessRecord], shellPID: pid_t, sessionId: String?) {
    // Once a claude PID is locked in, keep using it as long as it's still alive.
    // Re-searching every poll causes PID flipping when multiple sessions in the
    // same folder produce multiple candidates with non-deterministic dictionary order.
    let pid: pid_t
    if claudePID > 0, snapshot[claudePID] != nil {
      pid = claudePID
    } else {
      pid = ProcessTreeAnalyzer.findClaudeProcess(in: snapshot, shellPID: shellPID, sessionId: sessionId)
      claudePID = pid
    }

    guard pid > 0, let record = snapshot[pid] else {
      emit(.inactive, cpu: 0, memory: 0)
      return
    }

    let cpu = record.cpu
    let memoryBytes = record.memoryKB * 1024

    cpuHistory.append(cpu)
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
    let pid = claudePID
    DispatchQueue.main.async { cb?(SessionMonitorInfo(state: state, cpu: cpu, memory: memory, pid: pid)) }
  }

  /// Test-only entry point: feeds a snapshot directly without going through ProcessPoller.
  func testHandleSnapshot(_ snapshot: [pid_t: ProcessPoller.ProcessRecord], shellPID: pid_t, sessionId: String?) {
    handleSnapshot(snapshot, shellPID: shellPID, sessionId: sessionId)
  }

  private func reportStats(cpu: Double, memory: UInt64) {
    let state = currentState
    let cb = onStateChange
    let pid = claudePID
    DispatchQueue.main.async { cb?(SessionMonitorInfo(state: state, cpu: cpu, memory: memory, pid: pid)) }
  }
}
