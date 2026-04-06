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
import Combine
import Foundation
import GhosttyEmbed
import GRDBQuery
import SwiftUI

/// ViewModel for ContentView managing session selection and window coordination
@MainActor
@Observable
final class ContentViewModel {
  // MARK: - State

  /// Currently selected session for this window (reflects focused pane in split mode)
  /// Currently selected session — set internally by extensions.
  var selectedSession: ClaudeSession?

  /// The split-pane tree for this window. `nil` when not in split mode.
  /// The split-pane tree — set internally by extensions.
  var splitTree: PaneSplitTree?

  /// Keeps GhosttyHostViews alive across SwiftUI view-tree restructuring (e.g. split transitions).
  /// SwiftUI destroys then recreates NSViewRepresentable wrappers when they move to a different
  /// structural position, which would kill the Ghostty process.  Holding a strong reference here
  /// prevents dealloc until the session is explicitly closed.
  @ObservationIgnored
  var ghosttyHostViews: [String: GhosttyHostView] = [:]

  /// Currently selected diff file (for diff viewer)
  var selectedDiffFile: GitChangedFile?

  /// Whether the window is configured with a session (triggers terminal render)
  private(set) var windowConfigured = false

  /// Reference to this view's window
  private(set) weak var currentWindow: NSWindow?

  // MARK: - Worktree Split State

  /// When non-nil, a split dialog is shown. Holds direction + source session info.
  var pendingSplit: PendingSplitRequest?

  /// Form data for the worktree creation dialog (Flow 1: git repo).
  var worktreeSplitForm: WorktreeSplitFormData?

  /// Error message from git operations (shown in dialog).
  var worktreeError: String?

  /// Whether a git operation is in progress.
  var isCreatingWorktree = false

  /// Whether the right-side inspector panel is visible.
  var showInspectorPanel = false

  /// Terminal ID currently being hovered with a file drag (drives header highlight).
  /// Set by AppKit drag callbacks (split mode) or SwiftUI isTargeted (single-pane).
  var fileDropTargetTerminalId: String?

  /// Cache: projectPath → IDEDetectionResult to avoid re-scanning on focus changes.
  @ObservationIgnored
  private var ideDetectionCache: [String: IDEDetectionResult] = [:]

  /// Session pending rename from context menu.
  var sessionToRename: ClaudeSession?
  var renameText: String = ""

  /// Maps tenvySessionId → source session ID for fork launches.
  @ObservationIgnored
  var pendingForkSessions: [String: String] = [:]

  /// Terminal IDs that should launch a plain shell instead of claude.
  @ObservationIgnored
  var plainTerminalIds: Set<String> = []

  /// Observable titles for plain terminals (updated by Ghostty surface title publisher).
  /// Claude sessions read titles from `sessionDiscovery.sessions` instead.
  var plainTerminalTitles: [String: String] = [:]

  /// Combine subscriptions for Ghostty surface title updates.
  @ObservationIgnored
  var titleCancellables: [String: AnyCancellable] = [:]

  /// Per-terminal init script overrides (keyed by tenvySessionId). Consumed on first access.
  @ObservationIgnored
  var splitInitScripts: [String: String] = [:]

  /// Observer for pane drag-ended-outside-window notifications.
  @ObservationIgnored
  private var paneDragObserver: NSObjectProtocol?

  // MARK: - Dependencies

  let appModel: AppModel
  var windowRegistry: any WindowRegistering { appModel.windowRegistry }
  var sessionDiscovery: any SessionDiscovery { appModel.sessionDiscovery }
  var runtimeState: SessionRuntimeRegistry { appModel.runtimeRegistry }

  init(appModel: AppModel) {
    self.appModel = appModel
    appModel.registerViewModel(self)

    paneDragObserver = NotificationCenter.default.addObserver(
      forName: .paneDragEndedNoTarget,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self,
            let tenvySessionId = notification.userInfo?[Notification.paneDragTenvySessionIdKey] as? String,
            self.ownsTerminal(tenvySessionId) else { return }
      self.handlePaneDragToNewWindow(tenvySessionId: tenvySessionId)
    }
  }

  deinit {
    if let paneDragObserver {
      NotificationCenter.default.removeObserver(paneDragObserver)
    }
  }

  // MARK: - GhosttyHostView Cache

  /// Also checks AppModel's transfer store for cross-window moves.
  func ghosttyHostView(for tenvySessionId: String) -> GhosttyHostView? {
    if let view = ghosttyHostViews[tenvySessionId] { return view }
    // Auto-pickup from cross-window transfer
    if let view = appModel.pickupTransfer(tenvySessionId: tenvySessionId) {
      ghosttyHostViews[tenvySessionId] = view
      return view
    }
    return nil
  }

  /// Stores a newly created GhosttyHostView so it survives view-tree restructuring.
  func cacheGhosttyHostView(_ view: GhosttyHostView, tenvySessionId: String) {
    ghosttyHostViews[tenvySessionId] = view
    // Subscribe to surface title changes for plain terminals
    if isPlainTerminal(tenvySessionId) {
      subscribePlainTerminalTitle(tenvySessionId: tenvySessionId, surface: view.surface)
    }
  }

  /// Subscribes to Ghostty surface title changes for plain terminals.
  /// Shared by cacheGhosttyHostView, receiveTransferredSession, and preloadForTransfer.
  func subscribePlainTerminalTitle(tenvySessionId: String, surface: GhosttyEmbedSurface?) {
    guard let surface else { return }
    titleCancellables[tenvySessionId] = surface.titlePublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] newTitle in
        self?.plainTerminalTitles[tenvySessionId] = newTitle.isEmpty ? "Terminal" : newTitle
      }
  }

  /// Removes the cached view, allowing it to deallocate and terminate its process.
  /// Cleanup is two-phase: the surface is removed from the view hierarchy immediately
  /// (so Ghostty's C layer stops accessing it), but the host view is kept alive until
  /// the next run-loop tick so `ghostty_surface_free` completes before the `SurfaceView`
  /// deallocates — otherwise the C-layer userdata pointer dangles (BAD_ACCESS).
  func evictGhosttyHostView(tenvySessionId: String) {
    guard let hostView = ghosttyHostViews.removeValue(forKey: tenvySessionId) else { return }
    titleCancellables.removeValue(forKey: tenvySessionId)
    plainTerminalTitles.removeValue(forKey: tenvySessionId)
    hostView.close()
    DispatchQueue.main.async { [hostView] in _ = hostView }
  }

  // MARK: - Computed Properties

  /// Whether split mode is active
  var isInSplitMode: Bool { splitTree != nil }

  /// Session IDs currently in this window's split tree.
  var splitSessionIds: Set<String> {
    guard let tree = splitTree else { return [] }
    return Set(tree.allSessions.map(\.id))
  }

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

    // If this window already has a different session, open as a split pane
    if let focused = selectedSession ?? primarySession {
      let sessionToOpen = appModel.activatedSessions[session.id] ?? session
      appModel.activateSession(sessionToOpen)
      insertSplitPane(sessionToOpen, at: focused.id, direction: .right)
      return
    }

    // Open in this window (no session yet)
    // Use activated session if available (preserves tenvySessionId for synced sessions)
    let sessionToSelect = appModel.activatedSessions[session.id] ?? session
    clearDetailSelection()
    setSelectedSession(sessionToSelect)
  }

  /// Open a session in a new window/tab (used by sidebar context menu).
  func openInNewWindow(_ session: ClaudeSession) {
    let sessionToOpen = appModel.activatedSessions[session.id] ?? session
    appModel.activateSession(sessionToOpen)
    windowRegistry.pendingSessionForNewTab = sessionToOpen
    currentWindow?.selectNextTab(nil)
    NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
  }

  /// Move an active split-pane session to a new window/tab.
  /// Transfers the host view without restarting the process.
  func moveToNewWindow(_ session: ClaudeSession) {
    guard isInSplitMode else { return }
    handleDragToNewWindow(sessionId: session.id)
  }

  /// Clear diff selection (return to terminal)
  func clearDetailSelection() {
    selectedDiffFile = nil
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
    // Evict cached host view so its process terminates.
    if let tenvySessionId = splitTree?.allSessions.first(where: { $0.id == id })?.tenvySessionId {
      evictGhosttyHostView(tenvySessionId: tenvySessionId)
    }
    appModel.deactivateSession(id)
    appModel.terminalInput.unregister(sessionId: id)

    guard let newTree = splitTree?.removing(sessionId: id) else {
      splitTree = nil
      return
    }

    let remaining = newTree.allSessions
    if remaining.count <= 1 {
      // Exit split mode — single session remains
      let survivor = remaining.first
      splitTree = nil
      selectedSession = survivor
      bindWindowToSession(survivor)
    } else {
      // Still in split mode with 2+ panes
      splitTree = newTree
      if selectedSession?.id == id {
        selectedSession = remaining.first
      }
      // Re-register window if the primary was closed
      if currentWindow?.sessionId == id, let newPrimary = remaining.first {
        bindWindowToSession(newPrimary)
      }
    }
  }

  /// Close a pane identified by tenvySessionId (called from the pane header close button).
  func closePaneByTerminalId(_ tenvySessionId: String) {
    let session: ClaudeSession?
    if let tree = splitTree {
      session = tree.allSessions.first(where: { $0.tenvySessionId == tenvySessionId })
    } else if selectedSession?.tenvySessionId == tenvySessionId {
      session = selectedSession
    } else {
      session = nil
    }
    guard let session else { return }
    handleCloseRequested(for: session)
  }

  /// Close all split panes and return to single-terminal mode.
  func closeSplit() {
    let primary = primarySession
    if let tree = splitTree {
      for session in tree.allSessions where session.id != primary?.id {
        evictGhosttyHostView(tenvySessionId: session.tenvySessionId)
        appModel.deactivateSession(session.id)
        appModel.terminalInput.unregister(sessionId: session.id)
      }
    }
    splitTree = nil
    selectedSession = primary
    bindWindowToSession(primary)
  }

  // MARK: - Session List Action Handler

  func handleSessionListAction(_ action: SessionListAction) {
    switch action {
    case .select(let session):
      selectSession(session)
    case .createNew(let session):
      createNewSession(session)
    case .openInNewWindow(let session):
      openInNewWindow(session)
    case .moveToNewWindow(let session):
      moveToNewWindow(session)
    }
  }

  // MARK: - Inspector Action Handler

  /// Handle actions from the InspectorPanelView.
  func handleInspectorAction(_ action: InspectorPanelView.Action, for session: ClaudeSession) {
    switch action {
    case .restartWithNewPermissions(let sessionId):
      restartSessionWithNewPermissions(session: session)
    }
  }

  /// Restart a session to apply updated permission settings.
  /// Kills the current process, evicts the Ghostty view, clears the modified flag,
  /// and lets SwiftUI recreate the terminal with the new `--settings` flag.
  private func restartSessionWithNewPermissions(session: ClaudeSession) {
    let runtimeInfo = runtimeState.info(for: session.id)

    // Kill the running process
    let pid = runtimeInfo.shellPid > 0 ? runtimeInfo.shellPid : runtimeInfo.pid
    if pid > 0 {
      ProcessManager.shared.terminateProcess(pid: pid)
    }

    // Evict the cached host view and bump the generation counter.
    // Evict the cached host view and reset runtime info. The `reset()` call regenerates
    // `ghosttyInstanceId`, which changes the `.id()` on the terminal view, forcing SwiftUI
    // to destroy the old NSViewRepresentable and create a fresh one (calling `makeNSView`).
    evictGhosttyHostView(tenvySessionId: session.tenvySessionId)
    runtimeInfo.reset()
  }

  // MARK: - Terminal Action Handler

  /// Central handler for all terminal actions.
  func handleTerminalAction(_ action: TerminalAction, for session: ClaudeSession) {
    switch action {
    case .focusGained:
      handleFocusGained(for: session.id)
    case .splitRequested(let direction):
      handleSplitRequested(direction: direction)
    case .stateChanged(let info):
      runtimeState.updateState(for: session.id, state: info.state, cpu: info.cpu, memory: info.memory, pid: info.pid)
    case .shellStarted(let pid):
      runtimeState.info(for: session.id).setShellPid(pid)
    case .sessionActivated(let id):
      appModel.markSessionActivated(id)
      appModel.trackSessionForHooks(id)
    case .inputReady(let proxy, let sessionId):
      appModel.terminalInput.register(proxy, for: sessionId)
    case .inputUnregistered(let sessionId):
      appModel.terminalInput.unregister(sessionId: sessionId)
    case .closeRequested:
      handleCloseRequested(for: session)
    case .renameRequested:
      sessionToRename = session
      renameText = session.title
    case .fileDragEntered, .fileDragExited, .fileDropped:
      // Handled by PaneLeafView directly
      break
    }
  }

  /// Commit a rename initiated from the terminal context menu.
  func commitRename() {
    guard let session = sessionToRename, !renameText.isEmpty else {
      sessionToRename = nil
      return
    }
    if isPlainTerminal(session.tenvySessionId) {
      // Plain terminal: set the Ghostty surface title directly
      ghosttyHostViews[session.tenvySessionId]?.surface?.rename(to: renameText)
    } else {
      // Claude session: update the JSONL file on disk
      do {
        try sessionDiscovery.renameSession(session, to: renameText)
      } catch {
        // Rename failed silently — session title stays unchanged
      }
    }
    currentWindow?.title = renameText
    sessionToRename = nil
  }

  /// Handle "Close Session" from the context menu.
  /// For active Claude sessions, shows a confirmation alert before terminating.
  /// For plain terminals or split panes, closes directly.
  private func handleCloseRequested(for session: ClaudeSession) {
    let isPlain = isPlainTerminal(session.tenvySessionId)
    let runtimeInfo = runtimeState.info(for: session.id)
    let isActive = !isPlain && runtimeInfo.state != .inactive

    if isActive {
      guard NSAlert.confirmTerminateSession(title: session.title) else { return }

      // Kill the claude process
      let pid = runtimeInfo.shellPid > 0 ? runtimeInfo.shellPid : runtimeInfo.pid
      if pid > 0 {
        ProcessManager.shared.terminateProcess(pid: pid)
      }
    }

    // Close the pane
    if isInSplitMode {
      closeSplitPane(id: session.id)
    } else {
      // Single terminal — deactivate and clear selection
      evictGhosttyHostView(tenvySessionId: session.tenvySessionId)
      appModel.deactivateSession(session.id)
      appModel.terminalInput.unregister(sessionId: session.id)
      runtimeInfo.reset()
      selectedSession = nil
      bindWindowToSession(nil)
    }
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

  /// Hook-event-driven session sync — replaces the old heuristic matching.
  /// Called by AppModel when a hook event arrives with both `tenvySessionId` and `claudeSessionId`.
  /// Finds the session with the matching `tenvySessionId` (which uses a temp UUID as its `id`)
  /// and swaps its `id` to the real Claude session ID. The terminal continues running
  /// without interruption because `tenvySessionId` (SwiftUI view identity) stays the same.
  func syncSessionFromHookEvent(tenvySessionId: String, claudeSessionId: String) {
    // Skip plain terminals — they don't have Claude sessions
    guard !isPlainTerminal(tenvySessionId) else { return }

    // Find the session with this tenvySessionId — check selected, split tree, or primary
    let allSessions: [ClaudeSession] = {
      var sessions = [ClaudeSession]()
      if let sel = selectedSession { sessions.append(sel) }
      if let tree = splitTree { sessions.append(contentsOf: tree.allSessions) }
      return sessions
    }()

    guard let current = allSessions.first(where: { $0.tenvySessionId == tenvySessionId }),
          current.isNewSession,
          current.id != claudeSessionId else { return }

    // Create synced session with Claude's real ID but same tenvySessionId
    let synced = ClaudeSession(
      id: claudeSessionId,
      title: current.title,
      projectPath: current.projectPath,
      workingDirectory: current.workingDirectory,
      lastModified: Date(),
      filePath: current.filePath,
      isNewSession: false,
      tenvySessionId: current.tenvySessionId
    )

    // Transfer runtime state (CPU/PID) from temp ID to real ID
    runtimeState.transferState(from: current.id, to: synced.id)

    // Update activated sessions
    appModel.deactivateSession(current.id)
    appModel.activateSession(synced)

    // Update split tree if in split mode
    if splitTree != nil {
      splitTree = splitTree?.replacing(sessionId: current.id, with: synced)
    }

    // Update selected session
    if selectedSession?.id == current.id {
      selectedSession = synced
      bindWindowToSession(synced)
    }
  }

  /// Called when window reference changes
  func setWindow(_ window: NSWindow?) {
    currentWindow = window
    // Register session when window becomes available
    if window != nil, let session = selectedSession {
      bindWindowToSession(session)
    }
  }

  // MARK: - IDE Detection

  /// Returns IDE detection result for a given session, using a cache.
  func ideDetectionResult(for session: ClaudeSession) -> IDEDetectionResult {
    let path = session.workingDirectory.isEmpty ? session.projectPath : session.workingDirectory
    guard !path.isEmpty else { return .empty }

    if let cached = ideDetectionCache[path] {
      return cached
    }

    let result = IDEDetectionService.detect(projectPath: path)
    ideDetectionCache[path] = result
    return result
  }

  // MARK: - Private

  /// Set selected session and handle registration
  func setSelectedSession(_ session: ClaudeSession?) {
    let oldSession = selectedSession

    // If same session ID, just update the reference without re-registering
    if let old = oldSession, let new = session, old.id == new.id {
      selectedSession = new
      appModel.activateSession(new)
      return
    }

    selectedSession = session
    bindWindowToSession(session)

    if let session {
      appModel.activateSession(session)
    }
  }

  /// Single point of truth for window-session binding.
  /// Unregisters the previous session (if different) and registers the new one.
  /// Pass `nil` to unbind the window entirely.
  func bindWindowToSession(_ session: ClaudeSession?) {
    guard let window = currentWindow else { return }
    // Unregister old session if it differs from the new one
    if let oldId = window.sessionId, oldId != session?.id {
      windowRegistry.unregister(sessionId: oldId)
    }
    if let session {
      windowRegistry.register(sessionId: session.id, for: window)
      window.sessionId = session.id
      window.title = session.title
      windowConfigured = true
    } else {
      window.sessionId = nil
      window.title = "Tenvy"
      windowConfigured = false
    }
  }
}
