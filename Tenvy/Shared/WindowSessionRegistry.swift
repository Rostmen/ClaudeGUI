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
import Foundation

/// Tracks which sessions are open in which windows to prevent duplicates
@MainActor
@Observable
final class WindowSessionRegistry {
  /// Maps window number to session ID
  private(set) var windowSessions: [Int: String] = [:]

  /// Session to open in the next new tab/window
  var pendingSessionForNewTab: ClaudeSession?

  init() {}

  /// Register a session as being open in a window
  func register(sessionId: String, for window: NSWindow) {
    windowSessions[window.windowNumber] = sessionId
  }

  /// Unregister a window (e.g., when closed)
  func unregister(window: NSWindow) {
    windowSessions.removeValue(forKey: window.windowNumber)
  }

  /// Get the session ID for a window
  func sessionId(for window: NSWindow) -> String? {
    windowSessions[window.windowNumber]
  }

  /// Unregister a session from all windows
  func unregister(sessionId: String) {
    windowSessions = windowSessions.filter { $0.value != sessionId }
  }

  /// Find the window that has a session open
  func window(for sessionId: String) -> NSWindow? {
    guard let windowNumber = windowSessions.first(where: { $0.value == sessionId })?.key else {
      return nil
    }
    return NSApplication.shared.windows.first { $0.windowNumber == windowNumber }
  }

  /// Check if a session is already open in another window
  func isSessionOpen(_ sessionId: String, excludingWindow window: NSWindow?) -> Bool {
    guard let existingWindowNumber = windowSessions.first(where: { $0.value == sessionId })?.key else {
      return false
    }
    // If we're excluding a window, check if it's a different window
    if let window = window {
      return existingWindowNumber != window.windowNumber
    }
    return true
  }

  /// Try to select a session - returns true if handled (switched to existing window), false if should open normally
  func selectSession(_ sessionId: String, currentWindow: NSWindow?) -> Bool {
    // Check if session is already open in another window
    if let existingWindow = window(for: sessionId),
       existingWindow.windowNumber != currentWindow?.windowNumber {
      // Bring the existing window to front
      existingWindow.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      return true
    }
    return false
  }
}
