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

// MARK: - Session Creation & Worktree Flows

extension ContentViewModel {

  /// Create and select a new session.
  /// Shows the worktree/new-session dialog with form data gathered from git state.
  func createNewSession(_ session: ClaudeSession) {
    let git = appModel.gitService
    let hasGitRepo = git.findRepoRoot(from: session.workingDirectory) != nil

    pendingSplit = PendingSplitRequest(
      direction: .right,
      sourceSession: session,
      hasGitRepo: hasGitRepo,
      isNewSessionFlow: true
    )
    worktreeSplitForm = prepareSplitForm(
      session: session,
      isNewSessionFlow: true
    )
  }

  /// Activates a new session in the current window or a new tab.
  func activateNewSession(_ session: ClaudeSession) {
    if selectedSession != nil {
      appModel.activateSession(session)
      windowRegistry.pendingSessionForNewTab = session
      currentWindow?.selectNextTab(nil)
      NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
      return
    }

    appModel.activateSession(session)
    setSelectedSession(session)
  }

  /// Called when the user requests a split from Ghostty's context menu.
  /// Intercepts the split to show a worktree dialog instead of immediately splitting.
  func handleSplitRequested(direction: SplitDirection = .right) {
    guard let focused = selectedSession ?? primarySession else { return }

    // Plain terminal splits skip the git dialog — just show shell init script
    if isPlainTerminal(focused.tenvySessionId) {
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
        repoRoot: focused.workingDirectory,
        hasSubmodules: false
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
    worktreeSplitForm = prepareSplitForm(
      session: focused,
      isNewSessionFlow: false,
      gitBranch: runtimeInfo.gitBranch
    )
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
      appModel.sessionStore.createSession(from: session)
      splitInitScripts[session.tenvySessionId] = form.initScript
      dismissSplitDialog()
      if pending.isNewSessionFlow { activateNewSession(session) }
      return
    }

    // Git initialized, branch tab, no new branch — open as-is on current branch
    if hasGitRepo && !needsBranch && !needsWorktree {
      let session = pending.sourceSession
      appModel.sessionStore.createSession(from: session, branchName: form.baseBranch)
      splitInitScripts[session.tenvySessionId] = form.initScript
      dismissSplitDialog()
      if pending.isNewSessionFlow { activateNewSession(session) }
      return
    }

    if needsWorktree {
      confirmWorktreeSplit()
    } else if needsBranch {
      confirmBranchCreation()
    } else if needsGitInit {
      isCreatingWorktree = true
      worktreeError = nil
      Task {
        do {
          try appModel.gitService.initGitRepo(at: form.repoRoot)
          isCreatingWorktree = false
          let session = pending.sourceSession
          appModel.sessionStore.createSession(from: session)
          splitInitScripts[session.tenvySessionId] = form.initScript
          dismissSplitDialog()
          if pending.isNewSessionFlow { activateNewSession(session) }
          appModel.refreshGitBranches()
        } catch {
          isCreatingWorktree = false
          worktreeError = error.localizedDescription
        }
      }
    }
  }

  /// Creates a worktree, optionally initializing git first.
  func confirmWorktreeSplit() {
    guard let pending = pendingSplit,
          let form = worktreeSplitForm else { return }

    isCreatingWorktree = true
    worktreeError = nil

    Task {
      do {
        if !pending.hasGitRepo && form.initGit {
          try appModel.gitService.initGitRepo(at: form.repoRoot)
        }

        try appModel.gitService.createWorktree(
          repoPath: form.repoRoot,
          newBranch: form.newBranchName,
          baseBranch: form.baseBranch,
          destinationPath: form.worktreePath,
          initSubmodules: form.initSubmodules,
          symlinkBuildArtifacts: form.symlinkBuildArtifacts
        )
        isCreatingWorktree = false

        let sessionWorkDir = GitService.worktreeWorkingDirectory(
          worktreePath: form.worktreePath,
          gitRoot: form.repoRoot,
          projectPath: pending.sourceSession.projectPath
        )

        if pending.isNewSessionFlow {
          let newSession = ClaudeSession(
            id: UUID().uuidString,
            title: "New Session",
            projectPath: pending.sourceSession.projectPath,
            workingDirectory: sessionWorkDir,
            lastModified: Date(),
            filePath: nil,
            isNewSession: true,
            tenvySessionId: form.tenvySessionId
          )
          appModel.sessionStore.createSession(from: newSession, branchName: form.newBranchName, worktreePath: form.worktreePath)
          splitInitScripts[newSession.tenvySessionId] = form.initScript
          dismissSplitDialog()
          activateNewSession(newSession)
        } else {
          performSplitWithWorktree(
            direction: pending.direction,
            worktreePath: form.worktreePath,
            workingDirectory: sessionWorkDir,
            branchName: form.newBranchName,
            forkSession: form.forkSession,
            sourceSession: pending.sourceSession,
            initScript: form.initScript,
            tenvySessionId: form.tenvySessionId
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
  func confirmBranchCreation() {
    guard let pending = pendingSplit,
          let form = worktreeSplitForm else { return }

    isCreatingWorktree = true
    worktreeError = nil

    Task {
      do {
        if !pending.hasGitRepo && form.initGit {
          try appModel.gitService.initGitRepo(at: form.repoRoot)
        }

        try appModel.gitService.createBranch(
          repoPath: form.repoRoot,
          newBranch: form.newBranchName,
          baseBranch: form.baseBranch
        )
        isCreatingWorktree = false
        let session = pending.sourceSession
        appModel.sessionStore.createSession(from: session, branchName: form.newBranchName)
        splitInitScripts[session.tenvySessionId] = form.initScript
        dismissSplitDialog()
        if pending.isNewSessionFlow { activateNewSession(session) }
        appModel.refreshGitBranches()
      } catch {
        isCreatingWorktree = false
        worktreeError = error.localizedDescription
      }
    }
  }

  /// Called when user chooses "Plain Terminal" in split or new session flow.
  func openPlainTerminalSplit(initScript: String? = nil, asPlainTerminal: Bool = false) {
    guard let pending = pendingSplit else { return }

    if pending.isNewSessionFlow {
      if asPlainTerminal {
        let newSession = ClaudeSession(
          id: UUID().uuidString, title: "Terminal",
          projectPath: pending.sourceSession.projectPath,
          workingDirectory: pending.sourceSession.workingDirectory,
          lastModified: Date(), filePath: nil, isNewSession: true
        )
        appModel.sessionStore.createSession(from: newSession, isPlainTerminal: true)
        plainTerminalIds.insert(newSession.tenvySessionId)
        if let initScript { splitInitScripts[newSession.tenvySessionId] = initScript }
        dismissSplitDialog()
        activateNewSession(newSession)
      } else {
        let session = pending.sourceSession
        appModel.sessionStore.createSession(from: session)
        if let initScript { splitInitScripts[session.tenvySessionId] = initScript }
        dismissSplitDialog()
        activateNewSession(session)
      }
      return
    }

    // Split flow: create plain terminal pane
    let newSession = ClaudeSession(
      id: UUID().uuidString, title: "Terminal",
      projectPath: pending.sourceSession.projectPath,
      workingDirectory: pending.sourceSession.workingDirectory,
      lastModified: Date(), filePath: nil, isNewSession: true
    )
    appModel.sessionStore.createSession(from: newSession, isPlainTerminal: true)
    plainTerminalIds.insert(newSession.tenvySessionId)
    if let initScript { splitInitScripts[newSession.tenvySessionId] = initScript }
    appModel.activateSession(newSession)
    insertSplitPane(newSession, at: pending.sourceSession.id, direction: pending.direction)
    dismissSplitDialog()
  }

  /// Cancel the split dialog.
  func cancelSplitDialog() {
    dismissSplitDialog()
  }

  /// Whether a given terminal should launch as a plain shell (no claude).
  func isPlainTerminal(_ tenvySessionId: String) -> Bool {
    plainTerminalIds.contains(tenvySessionId)
  }

  /// Returns and consumes the source session ID for fork, if applicable.
  func forkSourceSessionId(for tenvySessionId: String) -> String? {
    pendingForkSessions.removeValue(forKey: tenvySessionId)
  }

  /// Returns and consumes the per-split init script override, if any.
  func initScript(for tenvySessionId: String) -> String? {
    splitInitScripts.removeValue(forKey: tenvySessionId)
  }

  // MARK: - Worktree Split Helpers

  func performSplitWithWorktree(
    direction: SplitDirection,
    worktreePath: String,
    workingDirectory: String,
    branchName: String? = nil,
    forkSession: Bool,
    sourceSession: ClaudeSession,
    initScript: String? = nil,
    tenvySessionId: String? = nil
  ) {
    let newSession = ClaudeSession(
      id: UUID().uuidString,
      title: "New Session",
      projectPath: sourceSession.projectPath,
      workingDirectory: workingDirectory,
      lastModified: Date(),
      filePath: nil,
      isNewSession: !forkSession,
      tenvySessionId: tenvySessionId
    )
    appModel.sessionStore.createSession(
      from: newSession,
      branchName: branchName,
      worktreePath: worktreePath,
      forkSourceSessionId: forkSession ? sourceSession.id : nil
    )
    if forkSession {
      pendingForkSessions[newSession.tenvySessionId] = sourceSession.id
    }
    if let initScript {
      splitInitScripts[newSession.tenvySessionId] = initScript
    }
    appModel.activateSession(newSession)
    insertSplitPane(newSession, at: sourceSession.id, direction: direction)
  }

  func insertSplitPane(_ newSession: ClaudeSession, at sourceId: String, direction: SplitDirection) {
    if let tree = splitTree {
      splitTree = tree.inserting(newSession, at: sourceId, direction: direction)
    } else {
      let primary = primarySession ?? (selectedSession ?? newSession)
      let tree = PaneSplitTree(primary)
      splitTree = tree.inserting(newSession, at: sourceId, direction: direction)
    }
    selectedSession = newSession
  }

  func dismissSplitDialog() {
    pendingSplit = nil
    worktreeSplitForm = nil
    worktreeError = nil
    isCreatingWorktree = false
  }

  // MARK: - Form Assembly

  /// Gathers git state and builds form data for the worktree/new-session dialog.
  private func prepareSplitForm(
    session: ClaudeSession,
    isNewSessionFlow: Bool,
    gitBranch: String? = nil
  ) -> WorktreeSplitFormData {
    let git = appModel.gitService
    let hasGitRepo = gitBranch != nil || git.findRepoRoot(from: session.workingDirectory) != nil
    let repoRoot = git.findRepoRoot(from: session.workingDirectory) ?? session.workingDirectory

    let currentBranch: String
    let branches: [String]
    if hasGitRepo {
      branches = git.listLocalBranches(at: session.workingDirectory)
      currentBranch = gitBranch ?? git.currentBranch(at: session.workingDirectory) ?? "main"
    } else {
      branches = ["main"]
      currentBranch = "main"
    }

    let defaultBranchName = String.defaultBranchName(title: session.title)

    var form = WorktreeSplitFormData(
      baseBranch: currentBranch,
      newBranchName: defaultBranchName,
      worktreePath: "",
      availableBranches: branches,
      sourceSessionId: session.id,
      sourceIsNewSession: isNewSessionFlow || session.isNewSession,
      repoRoot: repoRoot,
      hasSubmodules: hasGitRepo ? git.hasSubmodules(repoRoot: repoRoot) : false
    )
    form.worktreePath = git.defaultWorktreePath(
      repoRoot: repoRoot,
      branchName: defaultBranchName,
      sessionId: form.tenvySessionId
    )
    return form
  }
}
