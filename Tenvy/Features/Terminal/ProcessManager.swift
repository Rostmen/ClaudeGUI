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
import Foundation
import AppKit

/// Manages terminal processes and ensures cleanup on app termination
final class ProcessManager {
  static let shared = ProcessManager()

  private var trackedPIDs: Set<pid_t> = []
  private let lock = NSLock()
  private var isSetup = false

  private init() {
    setup()
  }

  /// Setup termination handlers
  private func setup() {
    guard !isSetup else { return }
    isSetup = true

    // Handle normal app termination
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillTerminate),
      name: NSApplication.willTerminateNotification,
      object: nil
    )

    // Setup signal handlers for force quit / crash scenarios
    setupSignalHandlers()

    // Register atexit handler as last resort
    atexit {
      ProcessManager.shared.terminateAllProcesses()
    }
  }

  /// Setup signal handlers for SIGTERM, SIGINT, etc.
  private func setupSignalHandlers() {
    // SIGTERM - sent when app is terminated
    signal(SIGTERM) { _ in
      ProcessManager.shared.terminateAllProcesses()
      exit(0)
    }

    // SIGINT - sent on Ctrl+C
    signal(SIGINT) { _ in
      ProcessManager.shared.terminateAllProcesses()
      exit(0)
    }

    // SIGHUP - sent when terminal is closed
    signal(SIGHUP) { _ in
      ProcessManager.shared.terminateAllProcesses()
      exit(0)
    }
  }

  @objc private func applicationWillTerminate(_ notification: Notification) {
    terminateAllProcesses()
  }

  /// Register a process PID to be tracked
  func registerProcess(pid: pid_t) {
    guard pid > 0 else { return }
    lock.lock()
    trackedPIDs.insert(pid)
    lock.unlock()
  }

  /// Unregister a process PID (e.g., when it terminates naturally)
  func unregisterProcess(pid: pid_t) {
    lock.lock()
    trackedPIDs.remove(pid)
    lock.unlock()
  }

  /// Check if there are any active tracked processes
  var hasActiveProcesses: Bool {
    lock.lock()
    let hasProcesses = !trackedPIDs.isEmpty
    lock.unlock()
    return hasProcesses
  }

  /// Get count of active processes
  var activeProcessCount: Int {
    lock.lock()
    let count = trackedPIDs.count
    lock.unlock()
    return count
  }

  /// Terminate all tracked processes and their children
  func terminateAllProcesses() {
    lock.lock()
    let pids = trackedPIDs
    trackedPIDs.removeAll()
    lock.unlock()

    for pid in pids {
      terminateProcessTree(pid: pid)
    }
  }

  /// Terminate a specific process and all its children
  func terminateProcess(pid: pid_t) {
    unregisterProcess(pid: pid)
    terminateProcessTree(pid: pid)
  }

  /// Terminate a process and all its descendants
  private func terminateProcessTree(pid: pid_t) {
    guard pid > 0 else { return }

    // First, find all child processes
    let children = findChildProcesses(of: pid)

    // Terminate children first (bottom-up)
    for childPid in children.reversed() {
      killProcess(childPid)
    }

    // Then terminate the parent
    killProcess(pid)
  }

  /// Find all descendant processes of a given PID using sysctl (no subprocess fork).
  /// Using Process()/ps would deadlock when Ghostty's SIGCHLD handler is active.
  private func findChildProcesses(of parentPid: pid_t) -> [pid_t] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    let count = size / MemoryLayout<kinfo_proc>.size
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
    guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }

    var parentMap: [pid_t: pid_t] = [:]
    var allPids: [pid_t] = []
    for proc in procs {
      let pid = proc.kp_proc.p_pid
      let ppid = proc.kp_eproc.e_ppid
      guard pid > 0 else { continue }
      parentMap[pid] = ppid
      allPids.append(pid)
    }

    var children: [pid_t] = []
    var queue: [pid_t] = [parentPid]
    var visited: Set<pid_t> = [parentPid]

    while !queue.isEmpty {
      let current = queue.removeFirst()
      for pid in allPids where parentMap[pid] == current && !visited.contains(pid) {
        visited.insert(pid)
        children.append(pid)
        queue.append(pid)
      }
    }

    return children
  }

  /// Kill a single process
  private func killProcess(_ pid: pid_t) {
    guard pid > 0 else { return }

    // First try SIGTERM for graceful shutdown
    kill(pid, SIGTERM)

    // Give it a moment to terminate gracefully
    usleep(100_000) // 100ms

    // Check if still running, then force kill
    if isProcessRunning(pid) {
      kill(pid, SIGKILL)
    }
  }

  /// Check if a process is still running
  private func isProcessRunning(_ pid: pid_t) -> Bool {
    // kill with signal 0 checks if process exists without sending a signal
    return kill(pid, 0) == 0
  }
}
