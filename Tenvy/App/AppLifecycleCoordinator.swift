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

/// Handles application-level quit confirmation.
/// Extracted from `AppDelegate` so the quit logic lives in one place and is
/// independently testable without instantiating the full delegate.
@MainActor
final class AppLifecycleCoordinator {
  static let suppressQuitAlertKey = "SuppressQuitAlertForActiveSessions"

  private(set) var isShowingAlert = false
  private(set) var userConfirmedQuit = false
  private let updater: any AppUpdating

  init(updater: any AppUpdating) {
    self.updater = updater
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Allow brew to quit silently during an in-progress update
    if updater.isUpdating { return .terminateNow }

    if userConfirmedQuit {
      userConfirmedQuit = false
      isShowingAlert = false
      return .terminateNow
    }

    guard !isShowingAlert else { return .terminateCancel }

    let suppressAlert = UserDefaults.standard.bool(forKey: Self.suppressQuitAlertKey)

    if ProcessManager.shared.hasActiveProcesses && !suppressAlert {
      isShowingAlert = true
      let shouldQuit = showQuitConfirmationAlert()
      isShowingAlert = false
      return shouldQuit ? .terminateNow : .terminateCancel
    }

    return .terminateNow
  }

  /// Shows quit confirmation alert and returns true if user wants to quit.
  func showQuitConfirmationAlert() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Quit Tenvy?"
    let sessionCount = ProcessManager.shared.activeProcessCount
    let sessionWord = sessionCount == 1 ? "session" : "sessions"
    alert.informativeText = "There \(sessionCount == 1 ? "is" : "are") \(sessionCount) active Claude \(sessionWord) running. Quitting will terminate \(sessionCount == 1 ? "it" : "them")."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "Don't ask again"

    let response = alert.runModal()

    if alert.suppressionButton?.state == .on {
      UserDefaults.standard.set(true, forKey: Self.suppressQuitAlertKey)
    }

    return response == .alertFirstButtonReturn
  }

  /// Called by `WindowDelegate` when the user confirmed quit from the window-close path.
  func markUserConfirmedQuit() {
    userConfirmedQuit = true
  }

  /// Called after `applicationShouldTerminate` runs to clear re-entrancy guard.
  func clearAlertState() {
    isShowingAlert = false
  }
}
