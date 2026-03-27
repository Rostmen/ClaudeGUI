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

import AppKit

/// Maps windows to session IDs to prevent duplicate session processes
@MainActor
protocol WindowRegistering: AnyObject {
  /// Session to open in the next new tab/window (set before opening a tab)
  var pendingSessionForNewTab: ClaudeSession? { get set }

  /// Associate a session ID with a window
  func register(sessionId: String, for window: NSWindow)

  /// Remove the mapping for a closed window
  func unregister(window: NSWindow)

  /// Remove all mappings for a session (session closed from any window)
  func unregister(sessionId: String)

  /// Return the session ID currently shown in a window
  func sessionId(for window: NSWindow) -> String?

  /// Return the window that is currently showing a session
  func window(for sessionId: String) -> NSWindow?

  /// True when the session is open in a window other than the excluded one
  func isSessionOpen(_ sessionId: String, excludingWindow window: NSWindow?) -> Bool

  /// If the session is already open in a different window, bring that window to front.
  /// Returns true if the session was handled (existing window made key), false otherwise.
  func selectSession(_ sessionId: String, currentWindow: NSWindow?) -> Bool
}

// MARK: - Conformance

extension WindowSessionRegistry: WindowRegistering {}
