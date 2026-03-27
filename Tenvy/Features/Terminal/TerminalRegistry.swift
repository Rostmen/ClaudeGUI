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

/// Registry that tracks active terminal input senders by session ID.
/// Used to route keyboard input from notifications to the running terminal backend.
@MainActor
final class TerminalRegistry {
  /// Weak references to terminal input senders by session ID
  private var terminals: [String: WeakTerminalRef] = [:]

  init() {}

  /// Register a terminal for a session
  func register(_ terminal: any TerminalInputSender, for sessionId: String) {
    terminals[sessionId] = WeakTerminalRef(terminal)
    cleanup()
  }

  /// Unregister a terminal view for a session
  func unregister(sessionId: String) {
    terminals.removeValue(forKey: sessionId)
  }

  /// Get the terminal sender for a session
  func terminal(for sessionId: String) -> (any TerminalInputSender)? {
    cleanup()
    return terminals[sessionId]?.terminal
  }

  /// Send text input to a session's terminal
  func sendInput(to sessionId: String, text: String) -> Bool {
    guard let terminal = terminal(for: sessionId) else { return false }
    terminal.send(txt: text)
    return true
  }

  /// Restart all active sessions
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
  func sendPermissionResponse(to sessionId: String, response: PermissionResponse) {
    guard let terminal = terminal(for: sessionId) else {
      print("TerminalRegistry: No terminal found for session \(sessionId)")
      return
    }
    switch response {
    case .allowOnce:
      terminal.send(txt: "\r")
    case .allowSession:
      terminal.send(txt: "\u{1B}[B")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        terminal.send(txt: "\r")
      }
    }
  }

  private func cleanup() {
    terminals = terminals.filter { $0.value.terminal != nil }
  }
}

/// Permission response options for notification actions
enum PermissionResponse {
  case allowOnce      // First option: Allow this once (Enter)
  case allowSession   // Second option: Allow for this session (↓ + Enter)
}

/// Weak reference wrapper for any terminal input sender
private class WeakTerminalRef {
  weak var terminal: (any TerminalInputSender)?

  init(_ terminal: any TerminalInputSender) {
    self.terminal = terminal
  }
}
