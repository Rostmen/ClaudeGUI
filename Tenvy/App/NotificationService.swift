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
@Observable
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

  /// Callback when user taps notification to open a session
  var onOpenSession: ((String) -> Void)?

  /// Track which sessions have pending notifications to avoid spamming
  private var pendingNotifications: Set<String> = []

  /// Track sessions currently waiting for input (for badge count)
  private var waitingSessions: Set<String> = []

  /// Whether the in-app notification permission prompt should be shown
  private(set) var shouldShowPrompt: Bool = false

  /// Whether the current authorization status is denied (needs System Settings)
  private(set) var authorizationDenied: Bool = false

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
    checkAuthorizationStatus()
  }

  /// Check current authorization status and surface the prompt if needed
  func checkAuthorizationStatus() {
    guard !AppSettings.shared.notificationPromptDismissed else { return }
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      Task { @MainActor [weak self] in
        guard let self else { return }
        switch settings.authorizationStatus {
        case .notDetermined:
          self.shouldShowPrompt = true
          self.authorizationDenied = false
        case .denied:
          self.shouldShowPrompt = true
          self.authorizationDenied = true
        case .authorized, .provisional, .ephemeral:
          self.shouldShowPrompt = false
          self.authorizationDenied = false
        @unknown default:
          break
        }
      }
    }
  }

  /// Request notification permission — called when user taps "Enable" in the prompt
  func requestPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
      if let error = error {
        print("Notification permission error: \(error)")
      }
      Task { @MainActor [weak self] in
        self?.shouldShowPrompt = false
      }
    }
  }

  /// Dismiss the prompt temporarily (will re-check next launch)
  func dismissPromptTemporarily() {
    shouldShowPrompt = false
  }

  /// Dismiss the prompt permanently
  func dismissPromptPermanently() {
    shouldShowPrompt = false
    AppSettings.shared.notificationPromptDismissed = true
  }

  /// Set up notification categories and actions
  private func setupNotificationCategories() {
    // Standard waiting notification - just open action
    let openAction = UNNotificationAction(
      identifier: openActionIdentifier,
      title: "Open Session",
      options: []
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
      options: []
    )

    let allowSessionAction = UNNotificationAction(
      identifier: allowSessionActionIdentifier,
      title: "Allow Session",
      options: []
    )

    let permissionCategory = UNNotificationCategory(
      identifier: permissionCategoryIdentifier,
      actions: [allowOnceAction, allowSessionAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )

    UNUserNotificationCenter.current().setNotificationCategories([waitingCategory, permissionCategory])
  }

  /// Mark a session as waiting for input (updates badge)
  func markSessionWaiting(sessionId: String, sessionName: String, isPermissionRequest: Bool = false, permissionMessage: String? = nil) {
    waitingSessions.insert(sessionId)
    updateDockBadge()
    // Always schedule — willPresent decides whether to surface it based on focus
    showNotification(sessionId: sessionId, sessionName: sessionName, isPermissionRequest: isPermissionRequest, permissionMessage: permissionMessage)
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

  /// Update the dock icon badge with count of waiting sessions not visible in the key window
  private func updateDockBadge() {
    let registry = WindowSessionRegistry.shared
    let keyWindowSessionId = NSApplication.shared.keyWindow.flatMap { registry.sessionId(for: $0) }
    let count = waitingSessions.filter { $0 != keyWindowSessionId }.count
    NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
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
  /// Handle notification when app is in foreground
  /// Suppress only if the session is already visible in the key window; show for all other windows
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    guard let sessionId = userInfo["sessionId"] as? String else {
      completionHandler([.banner, .sound, .list])
      return
    }

    Task { @MainActor in
      let registry = WindowSessionRegistry.shared
      let keyWindowSessionId = NSApplication.shared.keyWindow.flatMap { registry.sessionId(for: $0) }
      if keyWindowSessionId == sessionId {
        // User is already looking at this session — suppress
        completionHandler([])
      } else {
        // Session is in a background or different window — show it
        completionHandler([.banner, .sound, .list])
      }
    }
  }

  /// Handle notification tap and action buttons
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    
    NSApp.activate(ignoringOtherApps: true)
    
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
        TerminalRegistry.shared.sendPermissionResponse(to: sessionId, response: .allowOnce)
        // Optimistically clear waitingPermission — hook events will confirm the actual state
        AppState.shared.runtimeState.updateHookState(for: sessionId, state: .waiting, eventTime: Date())

      case self.allowSessionActionIdentifier:
        TerminalRegistry.shared.sendPermissionResponse(to: sessionId, response: .allowSession)
        AppState.shared.runtimeState.updateHookState(for: sessionId, state: .waiting, eventTime: Date())

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
