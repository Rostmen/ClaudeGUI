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

import Foundation
import IOKit.pwr_mgt

/// Prevents macOS from sleeping or starting the screen saver while at least one
/// scheduled-task-spawned session is alive.
///
/// Holds two `IOPMAssertion`s when the active set is non-empty:
/// - `PreventUserIdleSystemSleep` — blocks idle system sleep.
/// - `PreventUserIdleDisplaySleep` — blocks display sleep / screen saver.
///
/// Assertion ownership ends when the process exits (IOKit releases automatically),
/// but we also release explicitly when the last scheduled session is unregistered.
///
/// Tracking is keyed by `tenvySessionId` because it survives the temp-UUID → Claude
/// session-ID swap performed by `ContentViewModel.syncSessionFromHookEvent`. The
/// sync path deactivates the old id then reactivates the new one within a single
/// run-loop tick; a short debounce on `unregister` keeps the assertion stable
/// across that flicker.
@MainActor
final class ScheduledTaskPowerGuard {
  private var activeIds: Set<String> = []
  private var systemAssertionID: IOPMAssertionID = 0
  private var displayAssertionID: IOPMAssertionID = 0
  private var pendingReleases: [String: DispatchWorkItem] = [:]

  /// Delay before a `unregister` actually decrements the active set. Long enough
  /// to survive the deactivate-then-reactivate hop inside `syncSessionFromHookEvent`,
  /// short enough that closing a window feels immediate.
  private static let releaseDebounce: TimeInterval = 1.0

  private static let assertionReason = "Tenvy: scheduled Claude session running"

  /// Mark a session as active. Idempotent. Cancels any pending release for this id.
  func register(tenvySessionId: String) {
    pendingReleases.removeValue(forKey: tenvySessionId)?.cancel()
    let wasEmpty = activeIds.isEmpty
    activeIds.insert(tenvySessionId)
    if wasEmpty { acquireAssertions() }
  }

  /// Mark a session as no longer active. Debounced so a sync swap doesn't briefly
  /// drop the assertion. Idempotent for unknown ids.
  func unregister(tenvySessionId: String) {
    guard activeIds.contains(tenvySessionId) else { return }
    pendingReleases[tenvySessionId]?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.pendingReleases.removeValue(forKey: tenvySessionId)
      self.activeIds.remove(tenvySessionId)
      if self.activeIds.isEmpty { self.releaseAssertions() }
    }
    pendingReleases[tenvySessionId] = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDebounce, execute: work)
  }

  /// True when the guard currently holds power assertions. Exposed for tests/diagnostics.
  var isHoldingAssertions: Bool {
    systemAssertionID != 0 || displayAssertionID != 0
  }

  // MARK: - Private

  private func acquireAssertions() {
    if systemAssertionID == 0 {
      var id: IOPMAssertionID = 0
      let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        Self.assertionReason as CFString,
        &id
      )
      if result == kIOReturnSuccess { systemAssertionID = id }
    }
    if displayAssertionID == 0 {
      var id: IOPMAssertionID = 0
      let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        Self.assertionReason as CFString,
        &id
      )
      if result == kIOReturnSuccess { displayAssertionID = id }
    }
  }

  private func releaseAssertions() {
    if systemAssertionID != 0 {
      IOPMAssertionRelease(systemAssertionID)
      systemAssertionID = 0
    }
    if displayAssertionID != 0 {
      IOPMAssertionRelease(displayAssertionID)
      displayAssertionID = 0
    }
  }
}
