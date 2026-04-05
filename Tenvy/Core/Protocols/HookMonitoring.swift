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

/// Monitors ~/.claude/chat-sessions-events.jsonl and surfaces per-session HookState changes
@MainActor
protocol HookMonitoring: AnyObject {
  /// Callback fired when a session's state changes.
  /// Parameters: (sessionId, hookState, tool, permissionMessage, eventTimestamp, tenvySessionId)
  var onStateChange: ((String, HookState, String?, String?, Date?, String?) -> Void)? { get set }

  /// Open the events file and start watching for new lines
  func startMonitoring()

  /// Stop watching and close the file handle
  func stopMonitoring()

  /// Return the latest HookState for a session (nil if no events received yet)
  func state(for sessionId: String) -> HookState?

  /// Return the tool currently being used for a session, if any
  func currentTool(for sessionId: String) -> String?

  /// True if there has been any hook activity for the session in the last 5 minutes
  func hasRecentActivity(for sessionId: String) -> Bool

  /// Clear cached state for a single session
  func clearState(for sessionId: String)

  /// Clear all cached state (e.g. after hooks are uninstalled)
  func clearAllStates()
}

// MARK: - Conformance

extension HookEventService: HookMonitoring {}
