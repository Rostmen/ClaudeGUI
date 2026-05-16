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

/// Fixed 5-second tick loop that drives execution of due scheduled tasks.
///
/// Owned by `AppModel`. Wires a closure (`onTaskDue`) that the executor implements.
/// The scheduler itself is intentionally dumb — it queries the DB on each tick,
/// guards against re-entrancy with an in-process `inFlight` set, and hands off.
///
/// On `start()` it also performs missed-run reconciliation: any enabled task whose
/// `nextRunAt` is in the past gets rolled forward to the next valid slot without firing
/// the missed runs (per design — see `scheduled-tasks.md` §4.2).
@MainActor
final class ScheduledTaskScheduler {
  private let store: ScheduledTaskStore

  /// Set by `AppModel` after the executor exists. Receives a due task and runs the full
  /// execution flow (overlap check → worktree → window → session → prompt injection).
  var onTaskDue: ((ScheduledTaskRecord) async -> Void)?

  /// Tick interval, in seconds. Exposed for tests; production callers use the default.
  let tickInterval: TimeInterval

  private var timer: Timer?
  private var isStarted = false
  private var inFlight: Set<String> = []

  init(store: ScheduledTaskStore, tickInterval: TimeInterval = 5) {
    self.store = store
    self.tickInterval = tickInterval
  }

  // MARK: - Lifecycle

  func start() {
    guard !isStarted else { return }
    isStarted = true
    reconcileMissedRuns()
    let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
      // Timer callback fires on the run loop's thread (main, since we add to .main).
      // Dispatch into the main actor to keep the type system happy.
      Task { @MainActor in self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    isStarted = false
  }

  // MARK: - Tick

  /// Internal — exposed for test-driven manual ticking.
  func tick(now: Date = Date()) {
    guard let due = try? store.fetchDue(asOf: now), !due.isEmpty else { return }
    for task in due {
      guard !inFlight.contains(task.id) else { continue }
      inFlight.insert(task.id)
      Task { @MainActor [weak self] in
        defer { self?.inFlight.remove(task.id) }
        await self?.onTaskDue?(task)
      }
    }
  }

  // MARK: - Reconciliation

  /// Rolls `nextRunAt` forward for tasks whose due-time was missed while the app was closed.
  /// Per design: we do NOT execute the missed slot; we only re-schedule.
  func reconcileMissedRuns(now: Date = Date()) {
    guard let all = try? store.fetchAll() else { return }
    for task in all {
      guard task.enabled, task.nextRunAt < now else { continue }
      guard let freq = task.resolvedFrequency else { continue }
      let newNext = freq.nextRunAt(createdAt: task.createdAt, from: now)
      try? store.setNextRunAt(id: task.id, at: newNext)
    }
  }
}
