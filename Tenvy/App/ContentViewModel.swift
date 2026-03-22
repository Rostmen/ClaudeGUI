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

/// ViewModel for ContentView managing session selection and window coordination
@MainActor
@Observable
final class ContentViewModel {
  // MARK: - State

  /// Currently selected session for this window
  private(set) var selectedSession: ClaudeSession?

  /// Currently selected file path (for file editor)
  var selectedFilePath: String?

  /// Currently selected diff file (for diff viewer)
  var selectedDiffFile: GitChangedFile?

  /// Whether the window is configured with a session (triggers terminal render)
  private(set) var windowConfigured = false

  /// Reference to this view's window
  private(set) weak var currentWindow: NSWindow?

  // MARK: - Dependencies

  private var appState: AppState { AppState.shared }
  private var windowRegistry: WindowSessionRegistry { appState.windowRegistry }
  var sessionManager: SessionManager { appState.sessionManager }
  var runtimeState: SessionRuntimeState { appState.runtimeState }

  // MARK: - Computed Properties

  /// Whether terminal should be visible (no file or diff selected)
  var isTerminalVisible: Bool {
    selectedFilePath == nil && selectedDiffFile == nil
  }

  /// Whether to show empty state (nothing selected)
  var showEmptyState: Bool {
    selectedSession == nil && selectedFilePath == nil && selectedDiffFile == nil
  }

  /// Set of session IDs that are currently active (have a terminal running)
  var activeSessionIds: Set<String> {
    Set(appState.activatedSessions.keys)
  }

  /// Dictionary of activated sessions (for optimistic display of new sessions)
  var activatedSessions: [String: ClaudeSession] {
    appState.activatedSessions
  }

  /// Check if terminal should render for the given session
  func shouldRenderTerminal(for session: ClaudeSession) -> Bool {
    appState.isSessionActivated(session.id) &&
    windowConfigured &&
    currentWindow?.sessionId == session.id
  }

  // MARK: - Actions

  /// Try to select a session - switches to existing window/tab if already open, otherwise opens in new tab
  func selectSession(_ session: ClaudeSession) {
    // If clicking on the already selected session, just clear detail selection
    if selectedSession?.id == session.id {
      clearDetailSelection()
      return
    }

    // Check if session is already open in another window
    if windowRegistry.selectSession(session.id, currentWindow: currentWindow) {
      // Session was opened in another window, we switched to it
      return
    }

    // If this window already has a different session, open in a new tab
    if selectedSession != nil {
      // Store the session to open in the new tab
      // Use activated session if available (preserves terminalId)
      let sessionToOpen = appState.activatedSessions[session.id] ?? session
      windowRegistry.pendingSessionForNewTab = sessionToOpen
      // Open new tab - this triggers a new ContentView which will pick up the pending session
      currentWindow?.selectNextTab(nil)
      NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
      return
    }

    // Open in this window (no session yet)
    // Use activated session if available (preserves terminalId for synced sessions)
    let sessionToSelect = appState.activatedSessions[session.id] ?? session
    clearDetailSelection()
    setSelectedSession(sessionToSelect)
  }

  /// Create and select a new session
  /// Note: We don't add to sessionManager.sessions because Claude CLI will create
  /// its own session file with a different ID. The DirectoryMonitor will pick it up
  /// automatically when Claude creates the file.
  func createNewSession(_ session: ClaudeSession) {
    // If there's already a session in this window, open new session in a new tab
    if selectedSession != nil {
      appState.activateSession(session)
      windowRegistry.pendingSessionForNewTab = session
      currentWindow?.selectNextTab(nil)
      NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
      return
    }

    // No session in this window, open here
    appState.activateSession(session)
    setSelectedSession(session)
  }

  /// Clear file and diff selection (return to terminal)
  func clearDetailSelection() {
    selectedFilePath = nil
    selectedDiffFile = nil
  }

  /// Update runtime state for a session
  func updateRuntimeState(for sessionId: String, state: SessionState, cpu: Double, memory: UInt64, pid: pid_t) {
    runtimeState.updateState(for: sessionId, state: state, cpu: cpu, memory: memory, pid: pid)
  }

  /// Set shell PID for a session
  func setShellPid(_ pid: pid_t, for sessionId: String) {
    runtimeState.info(for: sessionId).setShellPid(pid)
  }

  // MARK: - Lifecycle

  /// Called when view appears - handles pending session for new tabs
  func handleAppear() {
    if let pendingSession = windowRegistry.pendingSessionForNewTab {
      windowRegistry.pendingSessionForNewTab = nil
      setSelectedSession(pendingSession)
      appState.activateSession(pendingSession)
    }
  }

  /// Sync new sessions with Claude-created session files
  /// When we create a new session, we use a temporary ID. Claude CLI creates its own
  /// session file with a different ID. This method finds the matching session and updates our reference.
  /// The terminal continues running without interruption by preserving the terminalId.
  func syncNewSessionWithDiscoveredSession() {
    guard let current = selectedSession, current.isNewSession else { return }

    // Find a session in the list that matches by working directory
    // and was created recently (within last minute)
    let recentThreshold = Date().addingTimeInterval(-60)
    if let matchingSession = sessionManager.sessions.first(where: { session in
      session.workingDirectory == current.workingDirectory &&
      session.lastModified > recentThreshold &&
      session.id != current.id
    }) {
      // Create a synced session that keeps the original terminalId
      // This prevents SwiftUI from recreating the terminal view
      let syncedSession = ClaudeSession(
        id: matchingSession.id,
        title: matchingSession.title,
        projectPath: matchingSession.projectPath,
        workingDirectory: matchingSession.workingDirectory,
        lastModified: matchingSession.lastModified,
        filePath: matchingSession.filePath,
        isNewSession: false,
        terminalId: current.terminalId  // Keep the original terminalId!
      )

      // Transfer runtime state from old session ID to new session ID
      runtimeState.transferState(from: current.id, to: syncedSession.id)

      // Update activated sessions
      appState.activatedSessions.removeValue(forKey: current.id)
      appState.activateSession(syncedSession)

      // Update selected session (terminal stays alive due to same terminalId)
      selectedSession = syncedSession

      // Update window registration
      if let window = currentWindow {
        windowRegistry.unregister(sessionId: current.id)
        configureWindow(window, for: syncedSession)
      }
    }
  }

  /// Called when window reference changes
  func setWindow(_ window: NSWindow?) {
    currentWindow = window
    // Register session when window becomes available
    if let window = window, let session = selectedSession {
      configureWindow(window, for: session)
    }
  }

  // MARK: - Private

  /// Set selected session and handle registration
  private func setSelectedSession(_ session: ClaudeSession?) {
    let oldSession = selectedSession

    // If same session ID, just update the reference without re-registering
    if let old = oldSession, let new = session, old.id == new.id {
      selectedSession = new
      appState.activateSession(new)
      return
    }

    selectedSession = session

    // Unregister old session from this window
    if let old = oldSession, let window = currentWindow {
      windowRegistry.unregister(sessionId: old.id)
      window.sessionId = nil
      windowConfigured = false
    }

    // Register and activate new session
    if let session = session {
      appState.activateSession(session)
      if let window = currentWindow {
        configureWindow(window, for: session)
      }
    } else if let window = currentWindow {
      window.title = "Tenvy"
      window.sessionId = nil
      windowConfigured = false
    }
  }

  /// Configure window for a session
  private func configureWindow(_ window: NSWindow, for session: ClaudeSession) {
    windowRegistry.register(sessionId: session.id, for: window)
    window.sessionId = session.id
    window.title = session.title
    windowConfigured = true
  }
}
