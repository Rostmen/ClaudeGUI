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

import SwiftUI

@main
struct ChatSessionsApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  init() {
    // Initialize ProcessManager early to setup termination handlers
    _ = ProcessManager.shared

    // Disable macOS window restoration - we want to start fresh with 1 window
    UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
  }

  var body: some Scene {
    WindowGroup(id: "main") {
      ContentView()
    }
    .windowStyle(.automatic)
    .defaultSize(width: 1200, height: 800)
    .commands {
      CommandGroup(after: .newItem) {
        Button("Import Session...") {
          NotificationCenter.default.post(name: .importSession, object: nil)
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
      }
    }

    Settings {
      SettingsView()
    }
  }
}

// MARK: - Notification Names for Menu Commands

extension Notification.Name {
  static let importSession = Notification.Name("importSession")
}

// MARK: - App Delegate

import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    NotificationService.shared.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NotificationService.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
  
  static let suppressQuitAlertKey = "SuppressQuitAlertForActiveSessions"
  private var isShowingAlert = false
  private var userConfirmedQuit = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    // Close any extra restored windows - we want exactly 1 window on launch
    let normalWindows = NSApplication.shared.windows.filter { window in
      window.isVisible && !window.isSheet && window.level == .normal
    }
    if normalWindows.count > 1 {
      // Keep the first window, close the rest
      for window in normalWindows.dropFirst() {
        window.close()
      }
    }

    // Set up window delegate for all existing windows
    for window in NSApplication.shared.windows {
      window.delegate = self
    }

    // Observe new window creation to set delegate for new windows/tabs
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWindowBecameKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )
  }

  @objc func handleWindowBecameKey(_ notification: Notification) {
    // Set delegate for any window that becomes key (ensures new windows get delegate)
    guard let window = notification.object as? NSWindow else { return }
    if window.delegate == nil || !(window.delegate is AppDelegate) {
      window.delegate = self
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Don't automatically terminate - we handle this in windowShouldClose
    return false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // If user already confirmed quit from windowShouldClose, allow termination
    if userConfirmedQuit {
      userConfirmedQuit = false
      isShowingAlert = false
      return .terminateNow
    }

    // Prevent re-entrancy if we're already showing an alert
    guard !isShowingAlert else {
      return .terminateCancel
    }

    // Check if we should suppress the alert
    let suppressAlert = UserDefaults.standard.bool(forKey: Self.suppressQuitAlertKey)

    // If there are active processes and we shouldn't suppress the alert
    if ProcessManager.shared.hasActiveProcesses && !suppressAlert {
      isShowingAlert = true
      let shouldQuit = showQuitConfirmationAlert()
      isShowingAlert = false

      if shouldQuit {
        return .terminateNow
      } else {
        return .terminateCancel
      }
    }

    return .terminateNow
  }

  /// Shows quit confirmation alert and returns true if user wants to quit
  private func showQuitConfirmationAlert() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Quit ChatSessions?"
    let sessionCount = ProcessManager.shared.activeProcessCount
    let sessionWord = sessionCount == 1 ? "session" : "sessions"
    alert.informativeText = "There \(sessionCount == 1 ? "is" : "are") \(sessionCount) active Claude \(sessionWord) running. Quitting will terminate \(sessionCount == 1 ? "it" : "them")."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "Don't ask again"

    let response = alert.runModal()

    // Save suppression preference if checked
    if alert.suppressionButton?.state == .on {
      UserDefaults.standard.set(true, forKey: Self.suppressQuitAlertKey)
    }

    return response == .alertFirstButtonReturn
  }
}

// MARK: - Window Delegate

/// Result of the window close confirmation dialog
private enum WindowCloseAction {
  case terminate  // Kill the process and close
  case cancel     // Don't close
}

extension AppDelegate: NSWindowDelegate {
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Prevent re-entrancy
    guard !isShowingAlert else {
      return false
    }

    // Check if this window has an active session
    let registry = WindowSessionRegistry.shared
    let appState = AppState.shared

    // Try to get session ID from registry first, then from window's associated object
    let sessionId = registry.sessionId(for: sender) ?? sender.sessionId

    if let sessionId = sessionId {
      let runtimeInfo = appState.runtimeState.info(for: sessionId)
      let isSessionActivated = appState.isSessionActivated(sessionId)

      // If session is activated (has a terminal), ask for confirmation
      // Check both: session in activatedSessions OR has a running process
      if isSessionActivated || runtimeInfo.shellPid > 0 {
        isShowingAlert = true
        let action = showWindowCloseConfirmationAlert()
        isShowingAlert = false

        switch action {
        case .cancel:
          return false

        case .terminate:
          // Kill the shell process (which kills Claude as child)
          if runtimeInfo.shellPid > 0 {
            ProcessManager.shared.terminateProcess(pid: runtimeInfo.shellPid)
          }
          // Reset runtime info
          runtimeInfo.reset()
          // Remove session from activated sessions
          appState.activatedSessions.removeValue(forKey: sessionId)
        }
      } else {
        // No active process, just remove from activated sessions
        appState.activatedSessions.removeValue(forKey: sessionId)
      }
    }

    // Unregister this window from the session registry
    registry.unregister(window: sender)
    sender.sessionId = nil  // Clear the associated object

    // Count how many windows will remain after this one closes
    let remainingWindows = NSApplication.shared.windows.filter { window in
      window != sender &&
      window.isVisible &&
      !window.isSheet &&
      window.level == .normal
    }

    // If there are other windows, just close this one (don't quit app)
    if !remainingWindows.isEmpty {
      return true
    }

    // This is the last window - handle quit confirmation
    let suppressAlert = UserDefaults.standard.bool(forKey: Self.suppressQuitAlertKey)

    if ProcessManager.shared.hasActiveProcesses && !suppressAlert {
      isShowingAlert = true
      let shouldQuit = showQuitConfirmationAlert()

      if shouldQuit {
        userConfirmedQuit = true
        NSApplication.shared.terminate(nil)
      } else {
        isShowingAlert = false
      }
      return false
    }

    // No active processes or alert suppressed - allow close and quit
    NSApplication.shared.terminate(nil)
    return false
  }

  /// Show confirmation dialog when closing a window with an active session
  private func showWindowCloseConfirmationAlert() -> WindowCloseAction {
    let alert = NSAlert()
    alert.messageText = "Close Window?"
    alert.informativeText = "This window has an active Claude session. Closing will terminate the session."
    alert.alertStyle = .warning
    let terminateButton = alert.addButton(withTitle: "Terminate Session")
    terminateButton.hasDestructiveAction = true
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
      return .terminate
    default:
      return .cancel
    }
  }

  func windowWillClose(_ notification: Notification) {
    // Window is closing - this is called after windowShouldClose returns true
    // or when we call terminate
  }
}

// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
  @Binding var window: NSWindow?

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        self.window = window
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear

        // Set window delegate to AppDelegate for close handling
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
          window.delegate = appDelegate
        }
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    // Update window reference if view moved to new window
    DispatchQueue.main.async {
      if let window = nsView.window, window != self.window {
        self.window = window
        // Set window delegate for the new window (important for new tabs)
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
          window.delegate = appDelegate
        }
        // Apply window styling
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
      }
    }
  }
}

// MARK: - NSWindow Session ID Extension

private var sessionIdKey: UInt8 = 0

extension NSWindow {
  /// Store session ID directly on the window using associated objects
  /// This provides a fallback when the registry doesn't have the mapping
  var sessionId: String? {
    get {
      objc_getAssociatedObject(self, &sessionIdKey) as? String
    }
    set {
      objc_setAssociatedObject(self, &sessionIdKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
}
