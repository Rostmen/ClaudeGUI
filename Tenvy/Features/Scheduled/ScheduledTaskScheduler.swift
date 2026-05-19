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
import GRDB

/// Event-driven scheduler for due scheduled tasks.
///
/// Owned by `AppModel`. Wires a closure (`onTaskDue`) that the executor implements.
///
/// **No polling.** A GRDB `ValueObservation` watches enabled tasks ordered by
/// `nextRunAt`. Whenever the DB changes (a task is added, edited, disabled, or
/// fired), the observation re-emits the current list and we re-schedule a single
/// one-shot `Timer` for the earliest future deadline. When the timer fires, any
/// task whose `nextRunAt` has passed is handed off to the executor; the executor's
/// writes (`markRunStarted`, etc.) trigger the same observation, which advances
/// the schedule for the next slot.
///
/// On `start()` it also performs missed-run reconciliation: any enabled task whose
/// `nextRunAt` is in the past gets rolled forward to the next valid slot without
/// firing the missed runs (per design — see `scheduled-tasks.md` §4.2).
@MainActor
final class ScheduledTaskScheduler {
  private let store: ScheduledTaskStore
  private let databaseReader: any DatabaseReader

  /// Set by `AppModel` after the executor exists. Receives a due task and runs the full
  /// execution flow (overlap check → worktree → window → session → prompt injection).
  var onTaskDue: ((ScheduledTaskRecord) async -> Void)?

  private var observationCancellable: AnyDatabaseCancellable?
  private var nextFireTimer: Timer?
  private var latestEnabledTasks: [ScheduledTaskRecord] = []
  private var isStarted = false
  private var inFlight: Set<String> = []

  init(store: ScheduledTaskStore, databaseReader: any DatabaseReader) {
    self.store = store
    self.databaseReader = databaseReader
  }

  // MARK: - Lifecycle

  func start() {
    guard !isStarted else { return }
    isStarted = true
    reconcileMissedRuns()
    subscribeToEnabledTasks()
  }

  func stop() {
    observationCancellable?.cancel()
    observationCancellable = nil
    nextFireTimer?.invalidate()
    nextFireTimer = nil
    latestEnabledTasks = []
    isStarted = false
  }

  // MARK: - Observation

  private func subscribeToEnabledTasks() {
    let observation = ValueObservation.tracking { db in
      try ScheduledTaskRecord
        .filter(Column("enabled") == true)
        .order(Column("nextRunAt").asc)
        .fetchAll(db)
    }
    observationCancellable = observation.start(
      in: databaseReader,
      scheduling: .async(onQueue: .main),
      onError: { _ in /* swallow — observation will re-fire on next write */ },
      onChange: { [weak self] tasks in
        Task { @MainActor [weak self] in
          self?.didReceiveTasks(tasks)
        }
      }
    )
  }

  private func didReceiveTasks(_ tasks: [ScheduledTaskRecord]) {
    latestEnabledTasks = tasks
    rescheduleAndFire()
  }

  // MARK: - Fire

  /// Fires any tasks whose deadline has passed and schedules a single one-shot timer
  /// for the earliest future deadline. Invoked from `didReceiveTasks` (DB change) and
  /// from the timer callback (deadline reached).
  private func rescheduleAndFire() {
    nextFireTimer?.invalidate()
    nextFireTimer = nil

    let now = Date()

    // Fire anything already due. The executor's writes will trigger the observation
    // to re-emit with updated `nextRunAt`, which advances the schedule.
    for task in latestEnabledTasks where task.nextRunAt <= now {
      fireTask(task)
    }

    // Schedule a single one-shot timer for the earliest future deadline.
    guard let next = latestEnabledTasks.first(where: { $0.nextRunAt > now }) else { return }
    let interval = max(0, next.nextRunAt.timeIntervalSinceNow)
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.rescheduleAndFire() }
    }
    RunLoop.main.add(timer, forMode: .common)
    nextFireTimer = timer
  }

  private func fireTask(_ task: ScheduledTaskRecord) {
    guard !inFlight.contains(task.id) else { return }
    inFlight.insert(task.id)
    Task { @MainActor [weak self] in
      defer { self?.inFlight.remove(task.id) }
      await self?.onTaskDue?(task)
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
