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

  /// Currently selected session for this window (reflects focused pane in split mode)
  private(set) var selectedSession: ClaudeSession?

  /// The split-pane tree for this window. `nil` when not in split mode.
  private(set) var splitTree: PaneSplitTree?

  /// Currently selected diff file (for diff viewer)
  var selectedDiffFile: GitChangedFile?

  /// Whether the window is configured with a session (triggers terminal render)
  private(set) var windowConfigured = false

  /// Reference to this view's window
  private(set) weak var currentWindow: NSWindow?

  // MARK: - Dependencies

  let appModel: AppModel
  private var windowRegistry: any WindowRegistering { appModel.windowRegistry }
  var sessionDiscovery: any SessionDiscovery { appModel.sessionDiscovery }
  var runtimeState: SessionRuntimeRegistry { appModel.runtimeRegistry }

  init(appModel: AppModel) {
    self.appModel = appModel
  }

  // MARK: - Computed Properties

  /// Whether split mode is active
  var isInSplitMode: Bool { splitTree != nil }

  /// The session registered to this window (the "primary" or first pane).
  /// When a split pane is focused, selectedSession may differ from this.
  var primarySession: ClaudeSession? {
    guard isInSplitMode else { return selectedSession }
    guard let windowSessionId = currentWindow?.sessionId else { return selectedSession }
    if selectedSession?.id == windowSessionId { return selectedSession }
    return appModel.activatedSessions[windowSessionId]
  }

  /// Whether terminal should be visible (no diff selected)
  var isTerminalVisible: Bool {
    selectedDiffFile == nil
  }

  /// Whether to show empty state (nothing selected)
  var showEmptyState: Bool {
    selectedSession == nil && selectedDiffFile == nil
  }

  /// Set of session IDs that are currently active (have a terminal running)
  var activeSessionIds: Set<String> {
    Set(appModel.activatedSessions.keys)
  }

  /// Dictionary of activated sessions (for optimistic display of new sessions)
  var activatedSessions: [String: ClaudeSession] {
    appModel.activatedSessions
  }

  /// True when the hook installation prompt should be shown
  var hookPromptVisible: Bool { appModel.hookSetup.shouldShowPrompt }

  /// True when the notification permission prompt should be shown
  var notificationPromptVisible: Bool { appModel.notifications.shouldShowPrompt }

  /// True when the update prompt should be shown
  var updatePromptVisible: Bool { appModel.updater.shouldShowPrompt }

  /// Check if terminal should render for the given session
  func shouldRenderTerminal(for session: ClaudeSession) -> Bool {
    guard appModel.isSessionActivated(session.id) && windowConfigured else { return false }
    // Primary session: must be registered to this window
    if currentWindow?.sessionId == session.id { return true }
    // Any session in the split tree is allowed in this window
    if splitTree?.contains(sessionId: session.id) == true { return true }
    return false
  }

  // MARK: - Actions

  /// Try to select a session - switches to existing window/tab if already open, otherwise opens in new tab
  func selectSession(_ session: ClaudeSession) {
    // If clicking on the already selected session, just clear detail selection
    if selectedSession?.id == session.id {
      clearDetailSelection()
      return
    }

    // In split mode, clicking any session in this window's tree just moves focus.
    if isInSplitMode, splitTree?.contains(sessionId: session.id) == true {
      handleFocusGained(for: session.id)
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
      let sessionToOpen = appModel.activatedSessions[session.id] ?? session
      windowRegistry.pendingSessionForNewTab = sessionToOpen
      // Open new tab - this triggers a new ContentView which will pick up the pending session
      currentWindow?.selectNextTab(nil)
      NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
      return
    }

    // Open in this window (no session yet)
    // Use activated session if available (preserves terminalId for synced sessions)
    let sessionToSelect = appModel.activatedSessions[session.id] ?? session
    clearDetailSelection()
    setSelectedSession(sessionToSelect)
  }

  /// Create and select a new session
  /// Note: We don't add to sessionDiscovery.sessions because Claude CLI will create
  /// its own session file with a different ID. The DirectoryMonitor will pick it up
  /// automatically when Claude creates the file.
  func createNewSession(_ session: ClaudeSession) {
    // If there's already a session in this window, open new session in a new tab
    if selectedSession != nil {
      appModel.activateSession(session)
      windowRegistry.pendingSessionForNewTab = session
      currentWindow?.selectNextTab(nil)
      NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
      return
    }

    // No session in this window, open here
    appModel.activateSession(session)
    setSelectedSession(session)
  }

  /// Clear diff selection (return to terminal)
  func clearDetailSelection() {
    selectedDiffFile = nil
  }

  /// Called when the user requests a split from Ghostty's context menu.
  /// Splits the focused pane in the given direction using the tree model.
  func handleSplitRequested(direction: SplitDirection = .right) {
    // The pane to split is whichever is currently focused.
    guard let focused = selectedSession ?? primarySession else { return }
    let newSession = ClaudeSession(
      id: UUID().uuidString,
      title: "New Session",
      projectPath: focused.projectPath,
      workingDirectory: focused.workingDirectory,
      lastModified: Date(),
      filePath: nil,
      isNewSession: true
    )
    appModel.activateSession(newSession)

    if let tree = splitTree {
      // Tree already exists — split the focused leaf.
      splitTree = tree.inserting(newSession, at: focused.id, direction: direction)
    } else {
      // First split: build tree from primary session then split it.
      let primary = primarySession ?? focused
      let tree = PaneSplitTree(primary)
      splitTree = tree.inserting(newSession, at: primary.id, direction: direction)
    }
    selectedSession = newSession
  }

  /// Update the ratio of a specific split node (called by the drag divider).
  func updateSplitRatio(splitId: UUID, ratio: Double) {
    splitTree = splitTree?.updatingRatio(splitId: splitId, ratio: ratio)
  }

  /// Called when a terminal pane gains focus — updates selectedSession so the sidebar
  /// highlights the correct session.
  func handleFocusGained(for sessionId: String) {
    if selectedSession?.id == sessionId { return }
    if let session = splitTree?.allSessions.first(where: { $0.id == sessionId }) {
      selectedSession = session
    } else if let primary = primarySession, primary.id == sessionId {
      selectedSession = primary
    }
  }

  /// Close a specific split pane by session ID.
  func closeSplitPane(id: String) {
    let wasSelected = selectedSession?.id == id
    appModel.deactivateSession(id)
    appModel.terminalInput.unregister(sessionId: id)

    if let newTree = splitTree?.removing(sessionId: id) {
      let remaining = newTree.allSessions
      if remaining.count <= 1 {
        // Only one pane left — exit split mode
        splitTree = nil
        if wasSelected { selectedSession = remaining.first ?? primarySession }
      } else {
        splitTree = newTree
        if wasSelected { selectedSession = primarySession ?? remaining.first }
      }
    } else {
      splitTree = nil
    }
  }

  /// Close all split panes and return to single-terminal mode.
  func closeSplit() {
    let primary = primarySession
    if let tree = splitTree {
      for session in tree.allSessions where session.id != primary?.id {
        appModel.deactivateSession(session.id)
        appModel.terminalInput.unregister(sessionId: session.id)
      }
    }
    splitTree = nil
    if let primary { selectedSession = primary }
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
      appModel.activateSession(pendingSession)
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
    if let matchingSession = sessionDiscovery.sessions.first(where: { session in
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
      appModel.deactivateSession(current.id)
      appModel.activateSession(syncedSession)

      // Update selected session (terminal stays alive due to same terminalId)
      selectedSession = syncedSession

      // Update window registration
      if let window = currentWindow {
        windowRegistry.unregister(sessionId: current.id)
        configureWindow(window, for: syncedSession)
      }
    }
  }

  /// Sync any new-session split panes with their Claude-created session files.
  func syncSplitSession() {
    guard let tree = splitTree else { return }
    let newSessions = tree.allSessions.filter { $0.isNewSession }
    guard !newSessions.isEmpty else { return }

    let recentThreshold = Date().addingTimeInterval(-60)
    var claimedIds: Set<String> = [selectedSession?.id].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
    var updatedTree = tree

    for current in newSessions {
      guard let matchingSession = sessionDiscovery.sessions.first(where: { s in
        s.workingDirectory == current.workingDirectory &&
        s.lastModified > recentThreshold &&
        s.id != current.id &&
        !claimedIds.contains(s.id)
      }) else { continue }

      claimedIds.insert(matchingSession.id)
      let synced = ClaudeSession(
        id: matchingSession.id,
        title: matchingSession.title,
        projectPath: matchingSession.projectPath,
        workingDirectory: matchingSession.workingDirectory,
        lastModified: matchingSession.lastModified,
        filePath: matchingSession.filePath,
        isNewSession: false,
        terminalId: current.terminalId
      )
      runtimeState.transferState(from: current.id, to: synced.id)
      appModel.deactivateSession(current.id)
      appModel.activateSession(synced)
      updatedTree = updatedTree.replacing(sessionId: current.id, with: synced)
      if selectedSession?.id == current.id { selectedSession = synced }
    }

    splitTree = updatedTree
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
      appModel.activateSession(new)
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
      appModel.activateSession(session)
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
