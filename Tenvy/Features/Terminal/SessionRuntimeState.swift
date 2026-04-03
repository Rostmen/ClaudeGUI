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
import Observation

/// Runtime info for a single session (state, CPU, PID, hook state)
/// Each session gets its own @Observable instance so only that row re-renders on updates.
@Observable
@MainActor
final class SessionRuntimeInfo {
  var state: SessionState = .inactive
  var cpu: Double = 0
  var memory: UInt64 = 0  // Memory usage in bytes
  var pid: pid_t = 0      // Claude process PID (for display)
  var shellPid: pid_t = 0 // Shell process PID (parent, for termination)

  // Hook-based state tracking
  var hookState: HookState?       // Current state from hooks (more accurate than CPU)
  var currentTool: String?        // Currently executing tool (if any)
  var hookTimestamp: Date?        // Last hook event timestamp
  var activatedAt: Date?          // When session was activated in app (to filter stale events)
  var hasUserInteracted: Bool = false  // True after first UserPromptSubmit (user sent a message)

  // Git branch tracking
  var gitBranch: String?          // Current git branch (nil if not a git repo)

  func update(state: SessionState, cpu: Double, memory: UInt64, pid: pid_t) {
    self.state = state
    self.cpu = cpu
    self.memory = memory
    self.pid = pid
  }

  func updateHookState(_ hookState: HookState, tool: String? = nil, eventTime: Date? = nil) {
    // Ignore events that happened before this session was activated in the app
    if let activatedAt = activatedAt, let eventTime = eventTime, eventTime < activatedAt {
      return
    }

    // Track when user first interacts (sends a message)
    if hookState == .processing {
      hasUserInteracted = true
    }

    // Before user interacts, only show "started" or "waiting" states
    // This ignores Claude's startup tool usage (MCP checks, plugin checks, etc.)
    if !hasUserInteracted {
      if hookState == .started || hookState == .waiting {
        self.hookState = hookState
        self.currentTool = nil
      }
      // Ignore thinking/processing states before user interaction
      return
    }

    self.hookState = hookState
    // Clear tool when waiting/waitingPermission/ended (Claude finished working)
    if hookState == .waiting || hookState == .waitingPermission || hookState == .ended {
      self.currentTool = nil
    } else {
      self.currentTool = tool
    }
    self.hookTimestamp = Date()
  }

  func markActivated() {
    self.activatedAt = Date()
    self.hasUserInteracted = false
    self.hookState = nil     // Don't carry stale state into a new session run
    self.currentTool = nil
  }

  func setShellPid(_ pid: pid_t) {
    self.shellPid = pid
  }

  func reset() {
    state = .inactive
    cpu = 0
    memory = 0
    pid = 0
    shellPid = 0
    hookState = nil
    currentTool = nil
    hookTimestamp = nil
    activatedAt = nil
    hasUserInteracted = false
    gitBranch = nil
  }
}

/// Registry that manages SessionRuntimeInfo instances by session ID.
/// Returns the same instance for the same ID, enabling fine-grained reactivity
/// where only the specific row that changed will re-render.
@MainActor
final class SessionRuntimeRegistry {
  private var instances: [String: SessionRuntimeInfo] = [:]

  /// Get or create a SessionRuntimeInfo for the given session ID.
  /// Always returns the same instance for the same ID.
  func info(for sessionId: String) -> SessionRuntimeInfo {
    if let existing = instances[sessionId] {
      return existing
    }
    let newInfo = SessionRuntimeInfo()
    instances[sessionId] = newInfo
    return newInfo
  }

  /// Update the runtime info for a session
  func updateState(for sessionId: String, state: SessionState, cpu: Double, memory: UInt64, pid: pid_t) {
    info(for: sessionId).update(state: state, cpu: cpu, memory: memory, pid: pid)
  }

  /// Remove a session's info (e.g., when session is deleted)
  func remove(sessionId: String) {
    instances.removeValue(forKey: sessionId)
  }

  /// Transfer runtime state from one session ID to another.
  /// Used when syncing a new session with its Claude-created file.
  /// Hook events may have already arrived under `newId` before sync completes,
  /// so hook state on the target is preserved if the source has none.
  func transferState(from oldId: String, to newId: String) {
    guard let oldInfo = instances[oldId] else { return }
    let newInfo = info(for: newId)

    // Always transfer process/CPU state from the old (monitored) session
    newInfo.state = oldInfo.state
    newInfo.cpu = oldInfo.cpu
    newInfo.memory = oldInfo.memory
    newInfo.pid = oldInfo.pid
    newInfo.shellPid = oldInfo.shellPid
    newInfo.gitBranch = oldInfo.gitBranch

    // Prefer hook state that's already on the target (from hook events arriving
    // under the real session ID before sync). Only copy from old if target has none.
    if newInfo.hookState == nil {
      newInfo.hookState = oldInfo.hookState
      newInfo.currentTool = oldInfo.currentTool
      newInfo.hookTimestamp = oldInfo.hookTimestamp
    }

    // Preserve activation tracking — use earliest activation time
    if let oldActivated = oldInfo.activatedAt {
      if newInfo.activatedAt == nil || oldActivated < newInfo.activatedAt! {
        newInfo.activatedAt = oldActivated
      }
    }
    newInfo.hasUserInteracted = oldInfo.hasUserInteracted || newInfo.hasUserInteracted

    // Remove old entry
    instances.removeValue(forKey: oldId)
  }

  /// Update hook state for a session
  func updateHookState(for sessionId: String, state: HookState, tool: String? = nil, eventTime: Date? = nil) {
    info(for: sessionId).updateHookState(state, tool: tool, eventTime: eventTime)
  }

  /// Mark a session as activated (terminal started in app)
  func markSessionActivated(_ sessionId: String) {
    info(for: sessionId).markActivated()
  }

  /// Reset hook states for all sessions (used when hooks are uninstalled)
  func resetAllHookStates() {
    for (_, info) in instances {
      info.hookState = nil
      info.currentTool = nil
      info.hookTimestamp = nil
    }
  }

  /// Reset a specific session's runtime info
  func reset(sessionId: String) {
    info(for: sessionId).reset()
  }
}

