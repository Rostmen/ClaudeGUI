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

import Darwin
import Dependencies
import Foundation

/// A shared, single-source-of-truth process snapshot updated every 500 ms.
///
/// Uses `sysctl(KERN_PROC_ALL)` + `KERN_PROCARGS2` + `proc_pidinfo` instead of
/// spawning a `ps` subprocess.  Spawning subprocesses via `Process()` deadlocks
/// when Ghostty is active because Ghostty installs a SIGCHLD handler that reaps
/// ALL child processes — including the `ps` child — before `waitUntilExit()` can
/// observe the exit.
actor ProcessPoller {
  static let shared = ProcessPoller()

  // MARK: - Types

  struct ProcessRecord {
    let pid: pid_t
    let ppid: pid_t
    let cpu: Double     // percentage (0–100)
    let memoryKB: UInt64
    let args: String
  }

  // MARK: - State

  private(set) var snapshot: [pid_t: ProcessRecord] = [:]
  private var listeners: [UUID: ([pid_t: ProcessRecord]) -> Void] = [:]
  private var pollingTask: Task<Void, Never>?

  // CPU delta tracking: previous cumulative CPU time (ns) per PID
  private var prevCPUTime: [pid_t: UInt64] = [:]
  private var prevPollDate: Date = Date()

  // MARK: - Dependencies

  private let clock: any Clock<Duration>

  private init() {
    @Dependency(\.continuousClock) var clk
    self.clock = clk
  }

  // MARK: - Public API

  func subscribe(id: UUID, handler: @escaping ([pid_t: ProcessRecord]) -> Void) {
    listeners[id] = handler
    startIfNeeded()
  }

  func unsubscribe(id: UUID) {
    listeners.removeValue(forKey: id)
    if listeners.isEmpty { stop() }
  }

  // MARK: - Private

  private func startIfNeeded() {
    guard pollingTask == nil else { return }
    pollingTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        await self.poll()
        try? await self.clock.sleep(for: .milliseconds(500))
      }
    }
  }

  private func stop() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  private func poll() {
    let now = Date()
    let elapsed = now.timeIntervalSince(prevPollDate)
    prevPollDate = now

    let result = Self.sysctlSnapshot(prevCPUTime: &prevCPUTime, elapsed: elapsed)
    snapshot = result
    for handler in listeners.values {
      handler(result)
    }
  }

  // MARK: - sysctl-based snapshot (no fork/subprocess)

  /// Builds a process snapshot using pure kernel syscalls.
  /// `KERN_PROC_ALL` → all PIDs + PPIDs in one call.
  /// `KERN_PROCARGS2` → full argv for each process.
  /// `proc_pidinfo(PROC_PIDTASKINFO)` → RSS + cumulative CPU time.
  /// CPU% is derived from the delta in cumulative CPU time between polls.
  static func sysctlSnapshot(
    prevCPUTime: inout [pid_t: UInt64],
    elapsed: TimeInterval
  ) -> [pid_t: ProcessRecord] {
    // --- 1. Fetch all kinfo_proc in one sysctl call ---
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [:] }

    let count = size / MemoryLayout<kinfo_proc>.size
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
    guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [:] }

    // --- 2. Build records ---
    var records: [pid_t: ProcessRecord] = [:]
    let elapsedNS = max(1, UInt64(elapsed * 1_000_000_000))

    for proc in procs {
      let pid  = proc.kp_proc.p_pid
      let ppid = proc.kp_eproc.e_ppid
      guard pid > 0 else { continue }

      // Memory + cumulative CPU time via proc_pidinfo
      var taskInfo = proc_taskinfo()
      let infoRet = withUnsafeMutablePointer(to: &taskInfo) { ptr in
        Darwin.proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr,
                            Int32(MemoryLayout<proc_taskinfo>.size))
      }
      let memoryKB: UInt64
      let cpuTimeNS: UInt64
      if infoRet >= Int32(MemoryLayout<proc_taskinfo>.size) {
        memoryKB  = taskInfo.pti_resident_size / 1024
        cpuTimeNS = taskInfo.pti_total_user + taskInfo.pti_total_system
      } else {
        memoryKB  = 0
        cpuTimeNS = 0
      }

      // CPU%: delta cumulative time ÷ wall-clock elapsed
      var cpuPercent = 0.0
      if let prev = prevCPUTime[pid], cpuTimeNS >= prev {
        cpuPercent = min(100.0, Double(cpuTimeNS - prev) / Double(elapsedNS) * 100.0)
      }
      prevCPUTime[pid] = cpuTimeNS

      // Full argv via KERN_PROCARGS2
      let args = processArgs(pid: pid)

      records[pid] = ProcessRecord(pid: pid, ppid: ppid,
                                   cpu: cpuPercent, memoryKB: memoryKB,
                                   args: args)
    }

    // Remove stale CPU entries for dead processes
    let livePIDs = Set(records.keys)
    for key in prevCPUTime.keys where !livePIDs.contains(key) {
      prevCPUTime.removeValue(forKey: key)
    }

    return records
  }

  /// Returns the full command-line string for `pid` using `KERN_PROCARGS2`.
  /// Format on disk: Int32 argc, then null-separated strings (exec path + args).
  private static func processArgs(pid: pid_t) -> String {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return "" }

    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return "" }

    // Skip the argc Int32
    var offset = 4

    // Collect null-terminated strings; the first is the executable path,
    // subsequent ones are the actual arguments.
    var parts: [String] = []
    var start = offset
    while offset < size {
      if buf[offset] == 0 {
        if offset > start {
          if let s = String(bytes: buf[start..<offset], encoding: .utf8), !s.isEmpty {
            parts.append(s)
          }
        }
        start = offset + 1
      }
      offset += 1
    }

    return parts.joined(separator: " ")
  }

  // MARK: - Legacy ps parser (used by tests via AppDependencies override)

  static func parsePs(output: String) -> [pid_t: ProcessRecord] {
    var records: [pid_t: ProcessRecord] = [:]
    for line in output.components(separatedBy: "\n").dropFirst() {
      let parts = line.trimmingCharacters(in: .whitespaces)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
      guard parts.count >= 5,
            let pid  = Int32(parts[0]),
            let ppid = Int32(parts[1]),
            let cpu  = Double(parts[2]),
            let rss  = UInt64(parts[3]) else { continue }
      let args = parts[4...].joined(separator: " ")
      records[pid] = ProcessRecord(pid: pid, ppid: ppid, cpu: cpu, memoryKB: rss, args: args)
    }
    return records
  }
}
