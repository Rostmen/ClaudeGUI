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

import Dependencies
import Foundation

/// A shared, single-source-of-truth process snapshot updated every 500 ms.
///
/// Before this actor, each active session ran its own `ps` subprocess every 500 ms.
/// With N open sessions that produced N concurrent `ps` invocations per interval.
/// `ProcessPoller` replaces all of them with **one** `ps` call, distributing the
/// result to every registered `SessionStateMonitor` subscriber.
actor ProcessPoller {
  static let shared = ProcessPoller()

  // MARK: - Types

  /// A single row from the `ps` snapshot.
  struct ProcessRecord {
    let pid: pid_t
    let ppid: pid_t
    let cpu: Double
    let memoryKB: UInt64
    let args: String
  }

  // MARK: - State

  private(set) var snapshot: [pid_t: ProcessRecord] = [:]
  private var listeners: [UUID: ([pid_t: ProcessRecord]) -> Void] = [:]
  private var pollingTask: Task<Void, Never>?

  // MARK: - Dependencies
  // Resolved at init time. Override with withDependencies { … } before creating the instance.

  private let processSnapshot: @Sendable () -> [pid_t: ProcessRecord]
  private let clock: any Clock<Duration>

  // MARK: - Lifecycle

  private init() {
    @Dependency(\.processSnapshot) var snapshot
    @Dependency(\.continuousClock) var clk
    self.processSnapshot = snapshot
    self.clock = clk
  }

  /// Subscribe to snapshot updates. Returns immediately; the handler is called
  /// on the actor's executor each time a new snapshot arrives.
  func subscribe(id: UUID, handler: @escaping ([pid_t: ProcessRecord]) -> Void) {
    listeners[id] = handler
    startIfNeeded()
  }

  /// Remove a subscription. Polling stops automatically when no subscribers remain.
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
    let result = processSnapshot()
    snapshot = result
    for handler in listeners.values {
      handler(result)
    }
  }

  // MARK: - ps Invocation

  /// Single `ps` call capturing pid, ppid, %cpu, rss, and args for every process.
  /// This is a pure function with no side effects beyond spawning one subprocess.
  static func runPs() -> [pid_t: ProcessRecord] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-eo", "pid,ppid,%cpu,rss,args"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return [:] }
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [:] }
    return parsePs(output: output)
  }

  /// Pure parser: convert raw `ps` output into a PID-keyed dictionary.
  static func parsePs(output: String) -> [pid_t: ProcessRecord] {
    var records: [pid_t: ProcessRecord] = [:]
    for line in output.components(separatedBy: "\n").dropFirst() {  // skip header
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
