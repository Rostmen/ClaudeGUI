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

/// Result of the window close confirmation dialog.
enum WindowCloseAction {
  case terminate  // Kill the process and close
  case cancel     // Don't close
}

/// Handles window close/lifecycle events.
/// Extracted from `AppDelegate` so window logic is isolated and testable.
/// Receives its dependencies via `init` rather than accessing singletons.
@MainActor
final class WindowDelegate: NSObject, NSWindowDelegate {
  private let appModel: AppModel
  private let lifecycleCoordinator: AppLifecycleCoordinator

  private var isShowingAlert = false

  init(appModel: AppModel, lifecycleCoordinator: AppLifecycleCoordinator) {
    self.appModel = appModel
    self.lifecycleCoordinator = lifecycleCoordinator
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Allow brew to close windows silently during an in-progress update
    if appModel.updater.isUpdating { return true }

    guard !isShowingAlert && !lifecycleCoordinator.isShowingAlert else { return false }

    let registry = appModel.windowRegistry
    let sessionId = registry.sessionId(for: sender) ?? sender.sessionId

    if let sessionId = sessionId {
      let runtimeInfo = appModel.runtimeRegistry.info(for: sessionId)
      let isSessionActivated = appModel.isSessionActivated(sessionId)

      // With Ghostty, shellPid is never set (Ghostty manages its own PTY).
      // Fall back to the sysctl-discovered claude PID for both the active-session
      // check and the kill target.
      let pidToKill = runtimeInfo.shellPid > 0 ? runtimeInfo.shellPid : runtimeInfo.pid
      if isSessionActivated || pidToKill > 0 {
        isShowingAlert = true
        let action = showWindowCloseConfirmationAlert()
        isShowingAlert = false

        switch action {
        case .cancel:
          return false
        case .terminate:
          if pidToKill > 0 {
            ProcessManager.shared.terminateProcess(pid: pidToKill)
          }
          runtimeInfo.reset()
          appModel.deactivateSession(sessionId)
        }
      } else {
        appModel.deactivateSession(sessionId)
      }
    }

    registry.unregister(window: sender)
    sender.sessionId = nil

    let remainingWindows = NSApplication.shared.windows.filter { window in
      window != sender && window.isVisible && !window.isSheet && window.level == .normal
    }

    if !remainingWindows.isEmpty { return true }

    // Last window — handle quit confirmation
    let suppressAlert = UserDefaults.standard.bool(forKey: AppLifecycleCoordinator.suppressQuitAlertKey)

    if ProcessManager.shared.hasActiveProcesses && !suppressAlert {
      isShowingAlert = true
      let shouldQuit = lifecycleCoordinator.showQuitConfirmationAlert()

      if shouldQuit {
        lifecycleCoordinator.markUserConfirmedQuit()
        NSApplication.shared.terminate(nil)
      } else {
        isShowingAlert = false
      }
      return false
    }

    NSApplication.shared.terminate(nil)
    return false
  }

  func windowWillClose(_ notification: Notification) {
    // Nothing to do here; cleanup happens in windowShouldClose.
  }

  // MARK: - Private

  private func showWindowCloseConfirmationAlert() -> WindowCloseAction {
    let alert = NSAlert()
    alert.messageText = "Close Window?"
    alert.informativeText = "This window has an active Claude session. Closing will terminate the session."
    alert.alertStyle = .warning
    let terminateButton = alert.addButton(withTitle: "Terminate Session")
    terminateButton.hasDestructiveAction = true
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    return response == .alertFirstButtonReturn ? .terminate : .cancel
  }
}
