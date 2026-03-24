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
import UserNotifications

// MARK: - Notification Names for Menu Commands

extension Notification.Name {
  static let importSession = Notification.Name("importSession")
}

// MARK: - App Entry Point

@main
struct TenvyApp: App {
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
      CommandGroup(replacing: .help) {
        Button("Report a Bug") {
          NSWorkspace.shared.open(URL(string: "https://github.com/Rostmen/ClaudeGUI/issues/new")!)
        }
      }
    }

    Settings {
      SettingsView()
    }
  }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private let lifecycleCoordinator = AppLifecycleCoordinator()
  private lazy var windowDelegate = WindowDelegate(
    appState: AppState.shared,
    lifecycleCoordinator: lifecycleCoordinator
  )

  private var releaseNotesWindow: NSWindow?
  private var pendingReleaseNotesVersion: String?
  private var releaseNotesShown = false

  // MARK: - UNUserNotificationCenterDelegate

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

  // MARK: - NSApplicationDelegate

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self

    // Close any extra restored windows - we want exactly 1 window on launch
    let normalWindows = NSApplication.shared.windows.filter {
      $0.isVisible && !$0.isSheet && $0.level == .normal
    }
    if normalWindows.count > 1 {
      for window in normalWindows.dropFirst() { window.close() }
    }

    // Set up window delegate for all existing windows
    for window in NSApplication.shared.windows {
      window.delegate = windowDelegate
    }

    // Observe new window creation to assign delegate for new windows/tabs
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWindowBecameKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )

    // Check for updates (at most once per day)
    UpdateService.shared.checkForUpdates()

    // Stash version; show release notes in applicationDidBecomeActive once the
    // main window is guaranteed visible.
    #if DEBUG
    AppSettings.shared.lastSeenVersion = ""  // Always show in debug builds
    #endif
    let currentVersion = AppInfo.version
    if currentVersion != AppSettings.shared.lastSeenVersion {
      AppSettings.shared.lastSeenVersion = currentVersion
      pendingReleaseNotesVersion = currentVersion
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    guard !releaseNotesShown, let version = pendingReleaseNotesVersion else { return }
    releaseNotesShown = true
    pendingReleaseNotesVersion = nil

    Task {
      let notes = await UpdateService.shared.fetchReleaseNotes(for: version)
      #if DEBUG
      let displayNotes = notes ?? "_(No release notes found for v\(version) on GitHub — this is a placeholder for debug builds.)_"
      #else
      guard let displayNotes = notes else { return }
      #endif
      await MainActor.run {
        self.showReleaseNotesWindow(version: version, notes: displayNotes)
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    lifecycleCoordinator.applicationShouldTerminate(sender)
  }

  // MARK: - Private

  @objc private func handleWindowBecameKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    if !(window.delegate is WindowDelegate) {
      window.delegate = windowDelegate
    }
  }

  private func showReleaseNotesWindow(version: String, notes: String) {
    let hostingView = NSHostingView(rootView: ReleaseNotesView(version: version, releaseNotes: notes))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "What's New in Tenvy \(version)"
    window.contentView = hostingView
    window.appearance = NSAppearance(named: .darkAqua)
    window.center()
    window.makeKeyAndOrderFront(nil)
    releaseNotesWindow = window
  }
}
