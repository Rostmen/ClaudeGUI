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

/// Shared application state across all windows
@MainActor
@Observable
final class AppState {
  static let shared = AppState()

  /// Shared session manager
  let sessionManager = SessionManager()

  /// Shared runtime state for all sessions (PIDs, CPU, etc.)
  let runtimeState = SessionRuntimeState()

  /// Hook event service for tracking Claude state via hooks
  let hookEventService = HookEventService.shared

  /// Hook installation service for auto-detection and installation
  let hookInstallationService = HookInstallationService.shared

  /// Notification service for system notifications
  let notificationService = NotificationService.shared

  /// Window session registry
  let windowRegistry = WindowSessionRegistry.shared

  /// Sessions that have been activated (have a terminal running)
  /// Shared across all windows so we don't spawn duplicate processes
  var activatedSessions: [String: ClaudeSession] = [:]

  /// Whether any app window is currently active
  var isWindowActive: Bool = true {
    didSet {
      notificationService.isWindowActive = isWindowActive
      // Clear notifications when window becomes active
      if isWindowActive {
        notificationService.clearAllNotifications()
      }
    }
  }

  private init() {
    setupHookEventService()
    setupNotificationService()
    setupWindowObservers()
  }

  /// Set up hook event monitoring
  private func setupHookEventService() {
    // Connect hook events to runtime state and installation service
    hookEventService.onStateChange = { [weak self] sessionId, hookState, tool, message, eventTime in
      Task { @MainActor in
        guard let self = self else { return }
        self.runtimeState.updateHookState(for: sessionId, state: hookState, tool: tool, eventTime: eventTime)
        // Notify installation service that we received a hook event
        self.hookInstallationService.receivedHookEvent(for: sessionId)

        // Send notification when waiting for input or permission
        if hookState == .waiting || hookState == .waitingPermission {
          let sessionName = self.activatedSessions[sessionId]?.title ?? ""
          let isPermission = hookState == .waitingPermission
          self.notificationService.notifyWaitingForInput(
            sessionId: sessionId,
            sessionName: sessionName,
            isPermissionRequest: isPermission,
            permissionMessage: message
          )
        } else {
          // Clear notification when state changes from waiting
          self.notificationService.clearNotification(for: sessionId)
        }
      }
    }

    // Start monitoring
    hookEventService.startMonitoring()
  }

  /// Set up notification service callbacks
  private func setupNotificationService() {
    notificationService.onOpenSession = { [weak self] sessionId in
      Task { @MainActor in
        self?.openSession(sessionId: sessionId)
      }
    }
  }

  /// Set up window activation observers
  private func setupWindowObservers() {
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.isWindowActive = true
      }
    }

    NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.isWindowActive = false
      }
    }
  }

  /// Open a session by ID (called from notification tap)
  func openSession(sessionId: String) {
    // Find the session
    guard let session = activatedSessions[sessionId] ?? sessionManager.sessions.first(where: { $0.id == sessionId }) else {
      return
    }

    // Bring app to front
    NSApplication.shared.activate(ignoringOtherApps: true)

    // Find a window showing this session or use the main window
    if let window = NSApplication.shared.windows.first(where: { $0.sessionId == sessionId }) {
      window.makeKeyAndOrderFront(nil)
    } else if let mainWindow = NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first {
      mainWindow.makeKeyAndOrderFront(nil)
      // Set pending session for the window to switch to
      windowRegistry.pendingSessionForNewTab = session
      // Post notification for ContentView to handle
      NotificationCenter.default.post(name: .openSessionFromNotification, object: session)
    }
  }

  /// Track a session for hook detection (called when terminal starts)
  func trackSessionForHooks(_ sessionId: String) {
    hookInstallationService.trackSession(sessionId)
  }

  /// Mark a session as activated (terminal started in app)
  /// Events before this time will be ignored
  func markSessionActivated(_ sessionId: String) {
    runtimeState.markSessionActivated(sessionId)
  }

  /// Activate a session (add to activated sessions if not already there)
  func activateSession(_ session: ClaudeSession) {
    if activatedSessions[session.id] == nil {
      activatedSessions[session.id] = session
    }
  }

  /// Check if a session is already activated
  func isSessionActivated(_ sessionId: String) -> Bool {
    activatedSessions[sessionId] != nil
  }
}

// MARK: - Notification Names

extension Notification.Name {
  /// Posted when user taps notification to open a session
  static let openSessionFromNotification = Notification.Name("openSessionFromNotification")
}
