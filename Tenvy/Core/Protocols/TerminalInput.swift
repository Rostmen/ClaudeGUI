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

// MARK: - TerminalInputSender

/// Common interface for sending input to any terminal backend (SwiftTerm or Ghostty).
@MainActor
protocol TerminalInputSender: AnyObject {
  func send(txt: String)
  func restartSession()
}

// MARK: - TerminalInput

/// Registry for active terminal views — used to route keyboard input from notifications
@MainActor
protocol TerminalInput: AnyObject {
  /// Register an active terminal for a session
  func register(_ terminal: any TerminalInputSender, for sessionId: String)

  /// Unregister a terminal view when its session closes
  func unregister(sessionId: String)

  /// Send raw text to a session's terminal PTY.
  /// Returns true if the terminal was found and the text was sent.
  @discardableResult
  func sendInput(to sessionId: String, text: String) -> Bool

  /// Send the appropriate keystrokes for a permission dialog response
  func sendPermissionResponse(to sessionId: String, response: PermissionResponse)

  /// Number of currently active (registered) terminal sessions
  var activeSessionCount: Int { get }

  /// Restart all active terminal sessions (called after hook install/uninstall)
  func restartAllSessions()

  /// Restart a single session's terminal
  func restartSession(for sessionId: String)
}

// MARK: - Conformance

extension TerminalRegistry: TerminalInput {}
