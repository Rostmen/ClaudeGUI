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
import SwiftTerm

/// Registry that tracks active terminal views by session ID
/// Used to send commands to terminals from notifications
@MainActor
final class TerminalRegistry {
  static let shared = TerminalRegistry()

  /// Weak references to terminal views by session ID
  private var terminals: [String: WeakTerminalRef] = [:]

  private init() {}

  /// Register a terminal view for a session
  func register(_ terminal: DraggableTerminalView, for sessionId: String) {
    terminals[sessionId] = WeakTerminalRef(terminal)
    cleanup()
  }

  /// Unregister a terminal view for a session
  func unregister(sessionId: String) {
    terminals.removeValue(forKey: sessionId)
  }

  /// Get the terminal view for a session
  func terminal(for sessionId: String) -> DraggableTerminalView? {
    cleanup()
    return terminals[sessionId]?.terminal
  }

  /// Send text input to a session's terminal
  func sendInput(to sessionId: String, text: String) -> Bool {
    guard let terminal = terminal(for: sessionId) else {
      return false
    }
    terminal.send(txt: text)
    return true
  }

  /// Restart all active sessions
  /// Used after hook installation/uninstallation to apply changes
  func restartAllSessions() {
    cleanup()
    for (_, weakRef) in terminals {
      weakRef.terminal?.restartSession()
    }
  }

  /// Get count of active sessions
  var activeSessionCount: Int {
    cleanup()
    return terminals.count
  }

  /// Send permission response to a session's terminal
  /// - Parameters:
  ///   - sessionId: The session ID
  ///   - response: The permission response type
  func sendPermissionResponse(to sessionId: String, response: PermissionResponse) {
    guard let terminal = terminal(for: sessionId) else {
      print("TerminalRegistry: No terminal found for session \(sessionId)")
      return
    }

    // Send the appropriate keystrokes based on response
    switch response {
    case .allowOnce:
      // First option is pre-selected — just press Enter
      terminal.send(txt: "\r")
    case .allowSession:
      // Arrow down to select second option, then Enter
      terminal.send(txt: "\u{1B}[B")  // Arrow down (ESC [ B)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        terminal.send(txt: "\r")
      }
    }
  }

  /// Remove any deallocated terminal references
  private func cleanup() {
    terminals = terminals.filter { $0.value.terminal != nil }
  }
}

/// Permission response options for notification actions
enum PermissionResponse {
  case allowOnce      // First option: Allow this once (Enter)
  case allowSession   // Second option: Allow for this session (↓ + Enter)
}

/// Weak reference wrapper for terminal views
private class WeakTerminalRef {
  weak var terminal: DraggableTerminalView?

  init(_ terminal: DraggableTerminalView) {
    self.terminal = terminal
  }
}
