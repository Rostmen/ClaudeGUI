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
import UserNotifications

/// Service for managing system notifications when Claude CLI is waiting for user input
@MainActor
final class NotificationService: NSObject {
  static let shared = NotificationService()

  /// Category identifier for session notifications
  private let categoryIdentifier = "SESSION_WAITING"

  /// Category identifier for permission notifications with actions
  private let permissionCategoryIdentifier = "PERMISSION_PROMPT"

  /// Action identifier for opening session
  private let openActionIdentifier = "OPEN_SESSION"

  /// Action identifiers for permission responses
  private let allowOnceActionIdentifier = "ALLOW_ONCE"
  private let allowSessionActionIdentifier = "ALLOW_SESSION"
  private let denyActionIdentifier = "DENY"

  /// Callback when user taps notification to open a session
  var onOpenSession: ((String) -> Void)?

  /// Track which sessions have pending notifications to avoid spamming
  private var pendingNotifications: Set<String> = []

  /// Track sessions currently waiting for input (for badge count)
  private var waitingSessions: Set<String> = []

  /// Whether the app window is currently active
  var isWindowActive: Bool = true {
    didSet {
      if isWindowActive {
        // Clear badge when app becomes active
        updateDockBadge()
      }
    }
  }

  private override init() {
    super.init()
    setupNotificationCategories()
    requestPermission()
  }

  /// Request notification permission
  func requestPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        print("Notification permission error: \(error)")
      }
    }
    UNUserNotificationCenter.current().delegate = self
  }

  /// Set up notification categories and actions
  private func setupNotificationCategories() {
    // Standard waiting notification - just open action
    let openAction = UNNotificationAction(
      identifier: openActionIdentifier,
      title: "Open Session",
      options: [.foreground]
    )

    let waitingCategory = UNNotificationCategory(
      identifier: categoryIdentifier,
      actions: [openAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )

    // Permission notification - with Allow/Deny actions
    let allowOnceAction = UNNotificationAction(
      identifier: allowOnceActionIdentifier,
      title: "Allow Once",
      options: []  // No foreground needed - runs in background
    )

    let allowSessionAction = UNNotificationAction(
      identifier: allowSessionActionIdentifier,
      title: "Allow Session",
      options: []
    )

    let denyAction = UNNotificationAction(
      identifier: denyActionIdentifier,
      title: "Deny",
      options: [.destructive]
    )

    let permissionCategory = UNNotificationCategory(
      identifier: permissionCategoryIdentifier,
      actions: [allowOnceAction, allowSessionAction, denyAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )

    UNUserNotificationCenter.current().setNotificationCategories([waitingCategory, permissionCategory])
  }

  /// Mark a session as waiting for input (updates badge)
  func markSessionWaiting(sessionId: String, sessionName: String, isPermissionRequest: Bool = false, permissionMessage: String? = nil) {
    waitingSessions.insert(sessionId)
    updateDockBadge()

    // Only show notification if window is not active
    if !isWindowActive {
      showNotification(sessionId: sessionId, sessionName: sessionName, isPermissionRequest: isPermissionRequest, permissionMessage: permissionMessage)
    }
  }

  /// Mark a session as no longer waiting (updates badge)
  func markSessionNotWaiting(sessionId: String) {
    waitingSessions.remove(sessionId)
    updateDockBadge()
    clearNotification(for: sessionId)
  }

  /// Send notification that a session is waiting for user input
  func notifyWaitingForInput(sessionId: String, sessionName: String, isPermissionRequest: Bool = false, permissionMessage: String? = nil) {
    markSessionWaiting(sessionId: sessionId, sessionName: sessionName, isPermissionRequest: isPermissionRequest, permissionMessage: permissionMessage)
  }

  /// Show the actual notification
  private func showNotification(sessionId: String, sessionName: String, isPermissionRequest: Bool = false, permissionMessage: String? = nil) {
    // Don't spam notifications for the same session
    guard !pendingNotifications.contains(sessionId) else { return }

    pendingNotifications.insert(sessionId)

    let content = UNMutableNotificationContent()
    if isPermissionRequest {
      content.title = "Permission Required"
      // Use permission message if available, otherwise generic message
      if let message = permissionMessage, !message.isEmpty {
        content.body = message
      } else {
        content.body = sessionName.isEmpty ? "Claude needs your permission to continue" : "\(sessionName) needs your permission"
      }
      // Use permission category with Allow/Deny actions
      content.categoryIdentifier = permissionCategoryIdentifier
    } else {
      content.title = "Claude is waiting"
      content.body = sessionName.isEmpty ? "Session is waiting for your input" : "\(sessionName) is waiting for your input"
      content.categoryIdentifier = categoryIdentifier
    }
    content.sound = .default
    content.userInfo = ["sessionId": sessionId]

    let request = UNNotificationRequest(
      identifier: "session-\(sessionId)",
      content: content,
      trigger: nil // Deliver immediately
    )

    UNUserNotificationCenter.current().add(request) { [weak self] error in
      if let error = error {
        print("Failed to schedule notification: \(error)")
        Task { @MainActor in
          self?.pendingNotifications.remove(sessionId)
        }
      }
    }
  }

  /// Update the dock icon badge with count of waiting sessions
  private func updateDockBadge() {
    let count = isWindowActive ? 0 : waitingSessions.count
    if count > 0 {
      NSApplication.shared.dockTile.badgeLabel = "\(count)"
    } else {
      NSApplication.shared.dockTile.badgeLabel = nil
    }
  }

  /// Clear pending notification for a session (e.g., when user starts typing)
  func clearNotification(for sessionId: String) {
    pendingNotifications.remove(sessionId)
    waitingSessions.remove(sessionId)
    updateDockBadge()
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["session-\(sessionId)"])
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["session-\(sessionId)"])
  }

  /// Clear all pending notifications
  func clearAllNotifications() {
    pendingNotifications.removeAll()
    waitingSessions.removeAll()
    updateDockBadge()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
  }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
  /// Handle notification when app is in foreground (we won't show it, but handle tap)
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Don't show notification if app is in foreground
    completionHandler([])
  }

  /// Handle notification tap and action buttons
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let actionIdentifier = response.actionIdentifier

    guard let sessionId = userInfo["sessionId"] as? String else {
      completionHandler()
      return
    }

    Task { @MainActor in
      self.pendingNotifications.remove(sessionId)
      self.waitingSessions.remove(sessionId)
      self.updateDockBadge()

      // Handle permission response actions
      switch actionIdentifier {
      case self.allowOnceActionIdentifier:
        // Send "y" to allow once
        TerminalRegistry.shared.sendPermissionResponse(to: sessionId, response: .allowOnce)

      case self.allowSessionActionIdentifier:
        // Send arrow down + enter for "allow session"
        TerminalRegistry.shared.sendPermissionResponse(to: sessionId, response: .allowSession)

      case self.denyActionIdentifier:
        // Send "n" to deny
        TerminalRegistry.shared.sendPermissionResponse(to: sessionId, response: .deny)

      case UNNotificationDefaultActionIdentifier:
        // User tapped notification body - open the session
        self.onOpenSession?(sessionId)

      case self.openActionIdentifier:
        // User tapped "Open Session" action
        self.onOpenSession?(sessionId)

      default:
        // Unknown action - just open the session
        self.onOpenSession?(sessionId)
      }
    }

    completionHandler()
  }
}
