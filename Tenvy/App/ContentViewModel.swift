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

// MARK: - Worktree Split Types

/// Holds pending split request info while the dialog is shown.
struct PendingSplitRequest {
  let direction: SplitDirection
  let sourceSession: ClaudeSession
  let hasGitRepo: Bool
  /// When true, the dialog creates a new standalone session (not a split pane).
  let isNewSessionFlow: Bool
  /// When true, the source is a plain terminal — only show shell init script options.
  let isPlainTerminalSplit: Bool

  init(direction: SplitDirection, sourceSession: ClaudeSession, hasGitRepo: Bool, isNewSessionFlow: Bool = false, isPlainTerminalSplit: Bool = false) {
    self.direction = direction
    self.sourceSession = sourceSession
    self.hasGitRepo = hasGitRepo
    self.isNewSessionFlow = isNewSessionFlow
    self.isPlainTerminalSplit = isPlainTerminalSplit
  }
}

/// Form data for the worktree creation dialog.
struct WorktreeSplitFormData {
  var baseBranch: String
  var newBranchName: String
  var worktreePath: String
  var forkSession: Bool = false
  var initSubmodules: Bool = true
  var symlinkBuildArtifacts: Bool = true
  var availableBranches: [String]
  let sourceSessionId: String
  let sourceIsNewSession: Bool
  let repoRoot: String
  var initScript: String = AppSettings.shared.shellInitScript

  /// Whether to run `git init` (only relevant when hasGitRepo == false)
  var initGit: Bool = false

  /// Whether to create a new branch (in new-session + git flow, or after git init)
  var createBranch: Bool = false

  /// Which git mode is active: branch-only or worktree
  var gitMode: GitMode = .worktree

  enum GitMode: String, CaseIterable {
    case branch = "Branch"
    case worktree = "Worktree"
  }
}

/// ViewModel for ContentView managing session selection and window coordination
@MainActor
@Observable
final class ContentViewModel {
  // MARK: - State

  /// Currently selected session for this window (reflects focused pane in split mode)
  private(set) var selectedSession: ClaudeSession?

  /// The split-pane tree for this window. `nil` when not in split mode.
  private(set) var splitTree: PaneSplitTree?

  /// Keeps GhosttyHostViews alive across SwiftUI view-tree restructuring (e.g. split transitions).
  /// SwiftUI destroys then recreates NSViewRepresentable wrappers when they move to a different
  /// structural position, which would kill the Ghostty process.  Holding a strong reference here
  /// prevents dealloc until the session is explicitly closed.
  @ObservationIgnored
  private var ghosttyHostViews: [String: GhosttyHostView] = [:]

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

  /// Cache: projectPath → IDEDetectionResult to avoid re-scanning on focus changes.
  @ObservationIgnored
  private var ideDetectionCache: [String: IDEDetectionResult] = [:]

  /// Session pending rename from context menu.
  var sessionToRename: ClaudeSession?
  var renameText: String = ""

  /// Maps terminalId → source session ID for fork launches.
  @ObservationIgnored
  private var pendingForkSessions: [String: String] = [:]

  /// Terminal IDs that should launch a plain shell instead of claude.
  @ObservationIgnored
  private var plainTerminalIds: Set<String> = []

  /// Observable titles for plain terminals (updated by Ghostty surface title publisher).
  /// Claude sessions read titles from `sessionDiscovery.sessions` instead.
  var plainTerminalTitles: [String: String] = [:]

  /// Combine subscriptions for Ghostty surface title updates.
  @ObservationIgnored
  private var titleCancellables: [String: AnyCancellable] = [:]

  /// Per-terminal init script overrides (keyed by terminalId). Consumed on first access.
  @ObservationIgnored
  private var splitInitScripts: [String: String] = [:]

  /// Observer for pane drag-ended-outside-window notifications.
  @ObservationIgnored
  private var paneDragObserver: NSObjectProtocol?

  // MARK: - Dependencies

  let appModel: AppModel
  private var windowRegistry: any WindowRegistering { appModel.windowRegistry }
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
            let terminalId = notification.userInfo?[Notification.paneDragTerminalIdKey] as? String,
            self.ownsTerminal(terminalId) else { return }
      self.handlePaneDragToNewWindow(terminalId: terminalId)
    }
  }

  deinit {
    if let paneDragObserver {
      NotificationCenter.default.removeObserver(paneDragObserver)
    }
  }

  // MARK: - GhosttyHostView Cache

  /// Returns the cached GhosttyHostView for the given terminal identity, if any.
  /// Also checks AppModel's transfer store for cross-window moves.
  func ghosttyHostView(for terminalId: String) -> GhosttyHostView? {
    if let view = ghosttyHostViews[terminalId] { return view }
    // Auto-pickup from cross-window transfer
    if let view = appModel.pickupTransfer(terminalId: terminalId) {
      ghosttyHostViews[terminalId] = view
      return view
    }
    return nil
  }

  /// Stores a newly created GhosttyHostView so it survives view-tree restructuring.
  func cacheGhosttyHostView(_ view: GhosttyHostView, terminalId: String) {
    ghosttyHostViews[terminalId] = view
    // Subscribe to surface title changes for plain terminals
    if isPlainTerminal(terminalId), let surface = view.surface {
      titleCancellables[terminalId] = surface.titlePublisher
        .receive(on: DispatchQueue.main)
        .sink { [weak self] newTitle in
          self?.plainTerminalTitles[terminalId] = newTitle.isEmpty ? "Terminal" : newTitle
        }
    }
  }

  /// Removes the cached view, allowing it to deallocate and terminate its process.
  /// Cleanup is two-phase: the surface is removed from the view hierarchy immediately
  /// (so Ghostty's C layer stops accessing it), but the host view is kept alive until
  /// the next run-loop tick so `ghostty_surface_free` completes before the `SurfaceView`
  /// deallocates — otherwise the C-layer userdata pointer dangles (BAD_ACCESS).
  func evictGhosttyHostView(terminalId: String) {
    guard let hostView = ghosttyHostViews.removeValue(forKey: terminalId) else { return }
    titleCancellables.removeValue(forKey: terminalId)
    plainTerminalTitles.removeValue(forKey: terminalId)
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
    // Use activated session if available (preserves terminalId for synced sessions)
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

  // MARK: - Drag & Drop Transfer

  /// Whether this ViewModel owns a terminal with the given terminalId.
  func ownsTerminal(_ terminalId: String) -> Bool {
    ghosttyHostViews[terminalId] != nil
  }

  /// Whether this ViewModel owns the given session (for cross-window transfer).
  func ownsSession(_ sessionId: String) -> Bool {
    if selectedSession?.id == sessionId { return true }
    if splitTree?.contains(sessionId: sessionId) == true { return true }
    return false
  }

  /// Release a session for transfer to another window.
  /// Extracts the host view (without closing it), deposits on AppModel,
  /// and removes the session from this window's split tree / selection.
  func prepareForTransfer(sessionId: String) {
    let session: ClaudeSession?
    if let s = splitTree?.allSessions.first(where: { $0.id == sessionId }) {
      session = s
    } else if selectedSession?.id == sessionId {
      session = selectedSession
    } else {
      return
    }
    guard let session else { return }

    // Extract host view WITHOUT closing — deposit for the destination to pick up
    if let hostView = ghosttyHostViews.removeValue(forKey: session.terminalId) {
      appModel.depositForTransfer(terminalId: session.terminalId, hostView: hostView)
    }

    // Remove from this window's structure (without deactivating — session stays alive)
    if isInSplitMode && splitTree?.contains(sessionId: sessionId) == true {
      let wasSelected = selectedSession?.id == sessionId
      let wasPrimary = currentWindow?.sessionId == sessionId

      if let newTree = splitTree?.removing(sessionId: sessionId) {
        let remaining = newTree.allSessions
        if remaining.count <= 1 {
          splitTree = nil
          if wasSelected { selectedSession = remaining.first ?? primarySession }
        } else {
          splitTree = newTree
          if wasSelected { selectedSession = primarySession ?? remaining.first }
        }
      } else {
        splitTree = nil
        if wasSelected { selectedSession = nil }
      }

      // Re-register window if the primary was removed
      if wasPrimary {
        bindWindowToSession(splitTree?.allSessions.first ?? selectedSession)
      }
    } else {
      // Single session — clear this window
      selectedSession = nil
      bindWindowToSession(nil)
    }

    // Close the now-empty window (unless it's the last visible one)
    if selectedSession == nil && !isInSplitMode, let window = currentWindow {
      let visibleWindows = NSApp.windows.filter { $0.isVisible && $0 != window }
      if !visibleWindows.isEmpty {
        window.close()
      }
    }
  }

  /// Receive a transferred session and insert it alongside an existing session.
  /// Called directly (same window) or via AppModel (cross-window).
  func receiveTransferredSession(_ session: ClaudeSession, alongside targetSessionId: String, direction: SplitDirection = .right) {
    if let hostView = appModel.pickupTransfer(terminalId: session.terminalId) {
      ghosttyHostViews[session.terminalId] = hostView
      // Re-subscribe to title updates for plain terminals
      if plainTerminalIds.contains(session.terminalId), let surface = hostView.surface {
        titleCancellables[session.terminalId] = surface.titlePublisher
          .receive(on: DispatchQueue.main)
          .sink { [weak self] newTitle in
            self?.plainTerminalTitles[session.terminalId] = newTitle.isEmpty ? "Terminal" : newTitle
          }
      }
    }
    appModel.activateSession(session)
    insertSplitPane(session, at: targetSessionId, direction: direction)
  }

  /// Handle a pane header dragged outside any window — open in a new window.
  private func handlePaneDragToNewWindow(terminalId: String) {
    // Find the session by terminalId
    guard let session = findSessionByTerminalId(terminalId) else { return }
    handleDragToNewWindow(sessionId: session.id)
  }

  /// Find a session by terminalId, searching local state and activated sessions.
  private func findSessionByTerminalId(_ terminalId: String) -> ClaudeSession? {
    if let tree = splitTree, let s = tree.allSessions.first(where: { $0.terminalId == terminalId }) {
      return s
    }
    if selectedSession?.terminalId == terminalId { return selectedSession }
    return appModel.activatedSessions.values.first(where: { $0.terminalId == terminalId })
  }

  /// Handle a session dragged to the "New Window" drop zone.
  /// Transfers the host view to a new window without restarting the process.
  func handleDragToNewWindow(sessionId: String) {
    guard let session = appModel.activatedSessions[sessionId] else { return }

    // Release from current location (deposits host view on AppModel)
    appModel.releaseSessionForTransfer(sessionId: sessionId)

    // The host view stays on AppModel's transfer store —
    // the new window's ViewModel picks it up via ghosttyHostView(for:) auto-pickup.
    appModel.activateSession(session)
    windowRegistry.pendingSessionForNewTab = session
    currentWindow?.selectNextTab(nil)
    NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
  }

  /// Create and select a new session
  /// Note: We don't add to sessionDiscovery.sessions because Claude CLI will create
  /// its own session file with a different ID. The DirectoryMonitor will pick it up
  /// automatically when Claude creates the file.
  func createNewSession(_ session: ClaudeSession) {
    // Check if the selected folder is under git control
    if let repoRoot = WorktreeService.findRepoRoot(from: session.workingDirectory) {
      let branches = GitBranchService.listLocalBranches(at: session.workingDirectory)
      let currentBranch = GitBranchService.currentBranch(at: session.workingDirectory) ?? "main"

      let dateFormatter = DateFormatter()
      dateFormatter.dateFormat = "MM-dd-yyyy-HH-mm"
      let defaultBranchName = "\(dateFormatter.string(from: Date()))-\(session.title)"
        .replacingOccurrences(of: " ", with: "-")
        .lowercased()

      pendingSplit = PendingSplitRequest(
        direction: .right,
        sourceSession: session,
        hasGitRepo: true,
        isNewSessionFlow: true
      )

      worktreeSplitForm = WorktreeSplitFormData(
        baseBranch: currentBranch,
        newBranchName: defaultBranchName,
        worktreePath: WorktreeService.defaultWorktreePath(repoRoot: repoRoot, branchName: defaultBranchName),
        forkSession: false,
        availableBranches: branches,
        sourceSessionId: session.id,
        sourceIsNewSession: true,
        repoRoot: repoRoot
      )
      return
    }

    // No git repo — show dialog so user can choose plain terminal or proceed
    let workDir = session.workingDirectory
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MM-dd-yyyy-HH-mm"
    let defaultBranchName = "\(dateFormatter.string(from: Date()))-\(session.title)"
      .replacingOccurrences(of: " ", with: "-")
      .lowercased()

    pendingSplit = PendingSplitRequest(
      direction: .right,
      sourceSession: session,
      hasGitRepo: false,
      isNewSessionFlow: true
    )

    worktreeSplitForm = WorktreeSplitFormData(
      baseBranch: "main",
      newBranchName: defaultBranchName,
      worktreePath: WorktreeService.defaultWorktreePath(repoRoot: workDir, branchName: defaultBranchName),
      availableBranches: ["main"],
      sourceSessionId: session.id,
      sourceIsNewSession: true,
      repoRoot: workDir
    )
  }

  /// Activates a new session in the current window or a new tab.
  private func activateNewSession(_ session: ClaudeSession) {
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
  /// Intercepts the split to show a worktree dialog instead of immediately splitting.
  func handleSplitRequested(direction: SplitDirection = .right) {
    guard let focused = selectedSession ?? primarySession else { return }

    // Plain terminal splits skip the git dialog — just show shell init script
    if isPlainTerminal(focused.terminalId) {
      pendingSplit = PendingSplitRequest(
        direction: direction,
        sourceSession: focused,
        hasGitRepo: false,
        isPlainTerminalSplit: true
      )
      worktreeSplitForm = WorktreeSplitFormData(
        baseBranch: "main",
        newBranchName: "",
        worktreePath: "",
        availableBranches: [],
        sourceSessionId: focused.id,
        sourceIsNewSession: true,
        repoRoot: focused.workingDirectory
      )
      return
    }

    let runtimeInfo = runtimeState.info(for: focused.id)
    let hasGitRepo = runtimeInfo.gitBranch != nil

    pendingSplit = PendingSplitRequest(
      direction: direction,
      sourceSession: focused,
      hasGitRepo: hasGitRepo
    )

    if hasGitRepo {
      let branches = GitBranchService.listLocalBranches(at: focused.workingDirectory)
      let currentBranch = runtimeInfo.gitBranch ?? "main"
      let repoRoot = WorktreeService.findRepoRoot(from: focused.workingDirectory) ?? focused.workingDirectory

      let dateFormatter = DateFormatter()
      dateFormatter.dateFormat = "MM-dd-yyyy-HH-mm"
      let defaultBranchName = "\(dateFormatter.string(from: Date()))-\(focused.title)"
        .replacingOccurrences(of: " ", with: "-")
        .lowercased()

      worktreeSplitForm = WorktreeSplitFormData(
        baseBranch: currentBranch,
        newBranchName: defaultBranchName,
        worktreePath: WorktreeService.defaultWorktreePath(repoRoot: repoRoot, branchName: defaultBranchName),
        availableBranches: branches,
        sourceSessionId: focused.id,
        sourceIsNewSession: focused.isNewSession,
        repoRoot: repoRoot
      )
    } else {
      // No git repo — still populate form for the unified dialog
      let workDir = focused.workingDirectory
      let dateFormatter2 = DateFormatter()
      dateFormatter2.dateFormat = "MM-dd-yyyy-HH-mm"
      let defaultBranchName = "\(dateFormatter2.string(from: Date()))-\(focused.title)"
        .replacingOccurrences(of: " ", with: "-")
        .lowercased()

      worktreeSplitForm = WorktreeSplitFormData(
        baseBranch: "main",
        newBranchName: defaultBranchName,
        worktreePath: WorktreeService.defaultWorktreePath(repoRoot: workDir, branchName: defaultBranchName),
        availableBranches: ["main"],
        sourceSessionId: focused.id,
        sourceIsNewSession: focused.isNewSession,
        repoRoot: workDir
      )
    }
  }

  /// Single entry point for the "Start" button in the unified dialog.
  /// Dispatches to the appropriate action based on form state.
  func confirmNewSessionDialog() {
    guard let pending = pendingSplit,
          let form = worktreeSplitForm else { return }

    let hasGitRepo = pending.hasGitRepo
    let needsGitInit = !hasGitRepo && form.initGit
    let needsBranch = form.createBranch && form.gitMode == .branch
    let needsWorktree = form.gitMode == .worktree && (hasGitRepo || (form.initGit && form.createBranch) || (!pending.isNewSessionFlow && form.initGit))

    // No git ops needed — just open the session
    if !hasGitRepo && !form.initGit {
      let session = pending.sourceSession
      splitInitScripts[session.terminalId] = form.initScript
      dismissSplitDialog()
      if pending.isNewSessionFlow {
        activateNewSession(session)
      }
      return
    }

    // Git initialized, branch tab, no new branch — open as-is on current branch
    if hasGitRepo && !needsBranch && !needsWorktree {
      let session = pending.sourceSession
      splitInitScripts[session.terminalId] = form.initScript
      dismissSplitDialog()
      if pending.isNewSessionFlow {
        activateNewSession(session)
      }
      return
    }

    if needsWorktree {
      confirmWorktreeSplit()
    } else if needsBranch {
      confirmBranchCreation()
    } else if needsGitInit {
      // Just git init, no branch/worktree
      isCreatingWorktree = true
      worktreeError = nil
      Task {
        do {
          try WorktreeService.initGitRepo(at: form.repoRoot)
          isCreatingWorktree = false
          let session = pending.sourceSession
          splitInitScripts[session.terminalId] = form.initScript
          dismissSplitDialog()
          if pending.isNewSessionFlow {
            activateNewSession(session)
          }
          appModel.refreshGitBranches()
        } catch {
          isCreatingWorktree = false
          worktreeError = error.localizedDescription
        }
      }
    }
  }

  /// Creates a worktree, optionally initializing git first.
  private func confirmWorktreeSplit() {
    guard let pending = pendingSplit,
          let form = worktreeSplitForm else { return }

    isCreatingWorktree = true
    worktreeError = nil

    Task {
      do {
        // Initialize git if needed (no-git flow)
        if !pending.hasGitRepo && form.initGit {
          try WorktreeService.initGitRepo(at: form.repoRoot)
        }

        try WorktreeService.createWorktree(
          repoPath: form.repoRoot,
          newBranch: form.newBranchName,
          baseBranch: form.baseBranch,
          destinationPath: form.worktreePath,
          initSubmodules: form.initSubmodules,
          symlinkBuildArtifacts: form.symlinkBuildArtifacts
        )
        isCreatingWorktree = false
        if pending.isNewSessionFlow {
          let newSession = ClaudeSession(
            id: UUID().uuidString,
            title: "New Session",
            projectPath: form.worktreePath,
            workingDirectory: form.worktreePath,
            lastModified: Date(),
            filePath: nil,
            isNewSession: true
          )
          splitInitScripts[newSession.terminalId] = form.initScript
          dismissSplitDialog()
          activateNewSession(newSession)
        } else {
          performSplitWithWorktree(
            direction: pending.direction,
            worktreePath: form.worktreePath,
            forkSession: form.forkSession,
            sourceSession: pending.sourceSession,
            initScript: form.initScript
          )
          dismissSplitDialog()
        }
        appModel.refreshGitBranches()
      } catch {
        isCreatingWorktree = false
        worktreeError = error.localizedDescription
      }
    }
  }

  /// Creates a new branch and opens the session at the same working directory.
  private func confirmBranchCreation() {
    guard let pending = pendingSplit,
          let form = worktreeSplitForm else { return }

    isCreatingWorktree = true
    worktreeError = nil

    Task {
      do {
        // Initialize git if needed (no-git flow)
        if !pending.hasGitRepo && form.initGit {
          try WorktreeService.initGitRepo(at: form.repoRoot)
        }

        try WorktreeService.createBranch(
          repoPath: form.repoRoot,
          newBranch: form.newBranchName,
          baseBranch: form.baseBranch
        )
        isCreatingWorktree = false
        let session = pending.sourceSession
        splitInitScripts[session.terminalId] = form.initScript
        dismissSplitDialog()
        if pending.isNewSessionFlow {
          activateNewSession(session)
        }
        appModel.refreshGitBranches()
      } catch {
        isCreatingWorktree = false
        worktreeError = error.localizedDescription
      }
    }
  }

  /// Called when user chooses "Plain Terminal" in split or new session flow.
  /// When `asPlainTerminal` is true, opens a plain shell; otherwise opens a Claude session.
  func openPlainTerminalSplit(initScript: String? = nil, asPlainTerminal: Bool = false) {
    guard let pending = pendingSplit else { return }

    if pending.isNewSessionFlow {
      if asPlainTerminal {
        // New session flow: open as plain terminal
        let newSession = ClaudeSession(
          id: UUID().uuidString,
          title: "Terminal",
          projectPath: pending.sourceSession.projectPath,
          workingDirectory: pending.sourceSession.workingDirectory,
          lastModified: Date(),
          filePath: nil,
          isNewSession: true
        )
        plainTerminalIds.insert(newSession.terminalId)
        if let initScript {
          splitInitScripts[newSession.terminalId] = initScript
        }
        dismissSplitDialog()
        activateNewSession(newSession)
      } else {
        // New session flow: open as Claude session (skip worktree)
        let session = pending.sourceSession
        if let initScript {
          splitInitScripts[session.terminalId] = initScript
        }
        dismissSplitDialog()
        activateNewSession(session)
      }
      return
    }

    // Split flow: create plain terminal pane
    let newSession = ClaudeSession(
      id: UUID().uuidString,
      title: "Terminal",
      projectPath: pending.sourceSession.projectPath,
      workingDirectory: pending.sourceSession.workingDirectory,
      lastModified: Date(),
      filePath: nil,
      isNewSession: true
    )
    plainTerminalIds.insert(newSession.terminalId)
    if let initScript {
      splitInitScripts[newSession.terminalId] = initScript
    }
    appModel.activateSession(newSession)
    insertSplitPane(newSession, at: pending.sourceSession.id, direction: pending.direction)
    dismissSplitDialog()
  }

  /// Cancel the split dialog.
  func cancelSplitDialog() {
    dismissSplitDialog()
  }

  /// Whether a given terminal should launch as a plain shell (no claude).
  func isPlainTerminal(_ terminalId: String) -> Bool {
    plainTerminalIds.contains(terminalId)
  }


  /// Returns and consumes the source session ID for fork, if applicable.
  func forkSourceSessionId(for terminalId: String) -> String? {
    pendingForkSessions.removeValue(forKey: terminalId)
  }

  /// Returns and consumes the per-split init script override, if any.
  func initScript(for terminalId: String) -> String? {
    splitInitScripts.removeValue(forKey: terminalId)
  }

  // MARK: - Worktree Split Helpers

  private func performSplitWithWorktree(
    direction: SplitDirection,
    worktreePath: String,
    forkSession: Bool,
    sourceSession: ClaudeSession,
    initScript: String? = nil
  ) {
    let newSession = ClaudeSession(
      id: UUID().uuidString,
      title: "New Session",
      projectPath: worktreePath,
      workingDirectory: worktreePath,
      lastModified: Date(),
      filePath: nil,
      isNewSession: !forkSession
    )
    if forkSession {
      pendingForkSessions[newSession.terminalId] = sourceSession.id
    }
    if let initScript {
      splitInitScripts[newSession.terminalId] = initScript
    }
    appModel.activateSession(newSession)
    insertSplitPane(newSession, at: sourceSession.id, direction: direction)
  }

  private func insertSplitPane(_ newSession: ClaudeSession, at sourceId: String, direction: SplitDirection) {
    if let tree = splitTree {
      splitTree = tree.inserting(newSession, at: sourceId, direction: direction)
    } else {
      let primary = primarySession ?? (selectedSession ?? newSession)
      let tree = PaneSplitTree(primary)
      splitTree = tree.inserting(newSession, at: sourceId, direction: direction)
    }
    selectedSession = newSession
  }

  private func dismissSplitDialog() {
    pendingSplit = nil
    worktreeSplitForm = nil
    worktreeError = nil
    isCreatingWorktree = false
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
    if let terminalId = splitTree?.allSessions.first(where: { $0.id == id })?.terminalId {
      evictGhosttyHostView(terminalId: terminalId)
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

  /// Move a pane from one position to another (same-window rearrange or cross-window transfer).
  func movePaneToSplit(sourceTerminalId: String, destinationTerminalId: String, zone: PaneDropZone) {
    guard sourceTerminalId != destinationTerminalId else { return }

    let direction = zone.splitDirection

    // Find destination session (must be in this window)
    let localSessions: [ClaudeSession]
    if let tree = splitTree {
      localSessions = tree.allSessions
    } else if let session = selectedSession {
      localSessions = [session]
    } else {
      return
    }
    guard let destSession = localSessions.first(where: { $0.terminalId == destinationTerminalId }) else { return }

    // Check if source is in this window
    if let sourceSession = localSessions.first(where: { $0.terminalId == sourceTerminalId }) {
      // Same-window move within split tree
      guard let tree = splitTree else { return }
      guard let newTree = tree.moving(sessionId: sourceSession.id, toDestination: destSession.id, direction: direction) else {
        return
      }
      let remaining = newTree.allSessions
      if remaining.count <= 1 {
        splitTree = nil
        selectedSession = remaining.first
        bindWindowToSession(remaining.first)
      } else {
        splitTree = newTree
        selectedSession = sourceSession
      }
    } else {
      // Cross-window: source is in another window
      guard let sourceSession = appModel.activatedSessions.values.first(where: { $0.terminalId == sourceTerminalId }) else { return }

      // Release from source window (deposits host view on AppModel)
      appModel.releaseSessionForTransfer(sessionId: sourceSession.id)

      // Receive into this window alongside the destination
      receiveTransferredSession(sourceSession, alongside: destSession.id, direction: direction)
    }
  }

  /// Close a pane identified by terminalId (called from the pane header close button).
  func closePaneByTerminalId(_ terminalId: String) {
    let session: ClaudeSession?
    if let tree = splitTree {
      session = tree.allSessions.first(where: { $0.terminalId == terminalId })
    } else if selectedSession?.terminalId == terminalId {
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
        evictGhosttyHostView(terminalId: session.terminalId)
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
    if isPlainTerminal(session.terminalId) {
      // Plain terminal: set the Ghostty surface title directly
      ghosttyHostViews[session.terminalId]?.surface?.rename(to: renameText)
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

  // MARK: - File Drop

  /// Terminal ID currently being hovered with a file drag (drives header highlight).
  /// Set by AppKit drag callbacks (split mode) or SwiftUI isTargeted (single-pane).
  var fileDropTargetTerminalId: String?

  /// Focuses the pane with the given terminal ID — used when files are dropped on a non-focused pane.
  func focusPane(terminalId: String) {
    guard let session = findSessionByTerminalId(terminalId),
          selectedSession?.terminalId != terminalId else { return }
    selectedSession = session
    ghosttyHostView(for: terminalId)?.makeFocused()
  }

  /// Handles file drop in single-pane mode (SwiftUI fallback).
  /// GhosttyHostView's AppKit drag handler doesn't fire in single-pane because
  /// SwiftUI's hosting layer intercepts drags before they reach child NSViews.
  func handleSinglePaneFileDrop(providers: [NSItemProvider], terminalId: String) -> Bool {
    guard let hostView = ghosttyHostView(for: terminalId) else { return false }

    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()

    for provider in providers {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        defer { group.leave() }
        guard let url else { return }
        lock.lock()
        urls.append(url)
        lock.unlock()
      }
    }

    group.notify(queue: .main) {
      guard !urls.isEmpty else { return }
      let text = urls
        .map { GhosttyHostView.shellEscape($0.path) }
        .joined(separator: " ")
      hostView.surface?.sendText(text)
    }
    return true
  }

  /// Handler for split-pane terminals that also auto-closes when the claude process ends.
  func handleSplitTerminalAction(_ action: TerminalAction, for session: ClaudeSession) {
    handleTerminalAction(action, for: session)
    if case .stateChanged(let info) = action,
       primarySession?.id != session.id && info.state == .inactive {
      closeSplitPane(id: session.id)
    }
  }

  /// Handle "Close Session" from the context menu.
  /// For active Claude sessions, shows a confirmation alert before terminating.
  /// For plain terminals or split panes, closes directly.
  private func handleCloseRequested(for session: ClaudeSession) {
    let isPlain = isPlainTerminal(session.terminalId)
    let runtimeInfo = runtimeState.info(for: session.id)
    let isActive = !isPlain && runtimeInfo.state != .inactive

    if isActive {
      // Show confirmation for active Claude sessions
      let alert = NSAlert()
      alert.messageText = "Close Session?"
      alert.informativeText = "This will terminate the active Claude session \"\(session.title)\"."
      alert.alertStyle = .warning
      let terminateButton = alert.addButton(withTitle: "Terminate")
      terminateButton.hasDestructiveAction = true
      alert.addButton(withTitle: "Cancel")

      guard alert.runModal() == .alertFirstButtonReturn else { return }

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
      evictGhosttyHostView(terminalId: session.terminalId)
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
      bindWindowToSession(syncedSession)
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
    if window != nil, let session = selectedSession {
      bindWindowToSession(session)
    }
  }

  // MARK: - IDE Detection

  /// Returns IDE detection result for a given session, using a cache.
  func ideDetectionResult(for session: ClaudeSession) -> IDEDetectionResult {
    let path = session.projectPath.isEmpty ? session.workingDirectory : session.projectPath
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
  private func setSelectedSession(_ session: ClaudeSession?) {
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
  private func bindWindowToSession(_ session: ClaudeSession?) {
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
