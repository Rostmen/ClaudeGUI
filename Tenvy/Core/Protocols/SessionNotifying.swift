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

/// Sends and manages macOS system notifications for Claude session state changes
@MainActor
protocol SessionNotifying: AnyObject {
  /// True when the in-app notification permission prompt should be shown
  var shouldShowPrompt: Bool { get }

  /// True when the user has denied notification permission (requires System Settings)
  var authorizationDenied: Bool { get }

  /// Mirrors app focus state — suppresses badge updates when active
  var isWindowActive: Bool { get set }

  /// Injected by AppModel so the service can look up which session is in the key window
  var windowRegistering: (any WindowRegistering)? { get set }

  /// Called when the user taps a notification to open a session
  var onOpenSession: ((String) -> Void)? { get set }

  /// Called when the user taps "Allow Once" or "Allow Session" on a permission notification.
  /// AppModel wires this to forward the response to `TerminalInput`.
  var onPermissionResponse: ((String, PermissionResponse) -> Void)? { get set }

  /// Called after a permission response to optimistically clear `waitingPermission` state.
  /// AppModel wires this to update `SessionRuntimeRegistry`.
  var onClearWaitingPermission: ((String) -> Void)? { get set }

  /// Send (or refresh) a notification that a session is waiting.
  /// Also updates the dock badge.
  func notifyWaitingForInput(
    sessionId: String,
    sessionName: String,
    isPermissionRequest: Bool,
    permissionMessage: String?
  )

  /// Remove the delivered notification for a session and clear the dedup guard
  func clearNotification(for sessionId: String)

  /// Remove all delivered notifications
  func clearAllNotifications()

  /// Re-check UNUserNotificationCenter authorization status
  func checkAuthorizationStatus()

  /// Request notification permission from the OS
  func requestPermission()

  /// Hide the in-app prompt until the next launch
  func dismissPromptTemporarily()

  /// Hide the in-app prompt permanently (stored in UserDefaults)
  func dismissPromptPermanently()
}

// MARK: - Conformance

extension NotificationService: SessionNotifying {}
