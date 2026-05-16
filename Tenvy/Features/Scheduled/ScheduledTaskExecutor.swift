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
import SwiftUI
import GRDBQuery

/// Errors surfaced by `ScheduledTaskExecutor`. Each gets a user-readable description
/// suitable for the `lastRunMessage` column and macOS notifications.
enum ScheduledTaskExecutorError: LocalizedError {
  case folderMissing(path: String)
  case notGitAndInitNotRequested
  case worktreeCreationFailed(String)
  case branchCollisionExhausted
  case promptFileMissing(path: String)
  case promptFileTooLarge(path: String, size: Int)
  case promptFileUnreadable(path: String, reason: String)

  var errorDescription: String? {
    switch self {
    case .folderMissing(let path):
      return "Working folder does not exist: \(path)"
    case .notGitAndInitNotRequested:
      return "Working folder is not a git repository."
    case .worktreeCreationFailed(let msg):
      return "Worktree creation failed: \(msg)"
    case .branchCollisionExhausted:
      return "Could not find an unused branch name after multiple attempts."
    case .promptFileMissing(let path):
      return "Prompt file not found: \(path)"
    case .promptFileTooLarge(let path, let size):
      return "Prompt file is too large (\(size) bytes): \(path)"
    case .promptFileUnreadable(let path, let reason):
      return "Could not read prompt file at \(path): \(reason)"
    }
  }
}

/// Builds a worktree, opens a background window, and inserts a session record for a
/// scheduled task firing. The actual Claude launch happens implicitly when the window's
/// `ContentView` mounts (the existing `shouldRenderTerminal` gate fires `makeNSView`).
///
/// Overlap detection, prompt injection, and notification dispatch are added in later
/// milestones; this milestone implements the happy path only.
@MainActor
final class ScheduledTaskExecutor {
  /// Maximum prompt-file size we'll read (bytes). 1 MB cap per design §9 #8.
  static let maxPromptFileSize = 1_048_576

  private let appModel: AppModel

  init(appModel: AppModel) {
    self.appModel = appModel
  }

  // MARK: - Public entry point

  func execute(_ task: ScheduledTaskRecord) async {
    let firedAt = Date()

    // Overlap rule (§4.4): inspect the prior spawned session before doing anything else.
    switch decideOverlap(task: task) {
    case .skip(let reason):
      handleSkipped(task: task, firedAt: firedAt, reason: reason)
      return
    case .closePriorThenProceed(let priorSessionId):
      closePriorSession(sessionId: priorSessionId)
    case .proceed:
      break
    }

    do {
      // Resolve the prompt up-front — fail the run early if a file prompt is missing or
      // unreadable, before we touch git or open a window.
      let promptText = try resolvePromptText(task: task)

      let prepared = try prepareWorktree(task: task, firedAt: firedAt)
      let session = makeSession(task: task, prepared: prepared, firedAt: firedAt)
      try insertSessionRecord(task: task, session: session, prepared: prepared, firedAt: firedAt)

      let nextRunAt = computeNextRun(task: task, from: firedAt)
      try appModel.scheduledTaskStore.markRunStarted(
        id: task.id,
        sessionId: session.tenvySessionId,
        runAt: firedAt,
        nextRunAt: nextRunAt
      )

      // Keep macOS awake while this scheduled session is alive. Released
      // (debounced) when the session is deactivated — see `AppModel.deactivateSession`.
      appModel.scheduledTaskPowerGuard.register(tenvySessionId: session.tenvySessionId)

      openBackgroundWindow(for: session, initialPrompt: promptText)
      handleStarted(task: task)
    } catch {
      handleFailure(task: task, error: error, firedAt: firedAt)
    }
  }

  // MARK: - Steps

  private func prepareWorktree(task: ScheduledTaskRecord, firedAt: Date) throws -> Prepared {
    let fm = FileManager.default
    guard fm.fileExists(atPath: task.workingDirectory) else {
      throw ScheduledTaskExecutorError.folderMissing(path: task.workingDirectory)
    }

    let git = appModel.gitService
    var repoRoot = git.findRepoRoot(from: task.workingDirectory)
    if repoRoot == nil {
      guard task.pendingGitInit else {
        throw ScheduledTaskExecutorError.notGitAndInitNotRequested
      }
      try git.initGitRepo(at: task.workingDirectory)
      repoRoot = task.workingDirectory
    }
    guard let repo = repoRoot else {
      throw ScheduledTaskExecutorError.notGitAndInitNotRequested
    }

    let baseBranch = git.currentBranch(at: repo) ?? "main"
    let slug = ScheduledTaskNaming.slug(name: task.name, fallbackId: task.id)
    let timestamp = ScheduledTaskNaming.timestamp(firedAt)
    let worktreeBase: String = {
      if let custom = task.customWorktreeBase, !custom.isEmpty {
        return custom
      }
      return (repo as NSString).appendingPathComponent(".claude/worktrees")
    }()
    try? fm.createDirectory(atPath: worktreeBase, withIntermediateDirectories: true)

    let hasSubmodules = git.hasSubmodules(repoRoot: repo)

    for attempt in 0...9 {
      let suffix: Int? = attempt == 0 ? nil : attempt
      let branchName = ScheduledTaskNaming.branchName(
        slug: slug, timestamp: timestamp, collisionSuffix: suffix
      )
      let dirName = ScheduledTaskNaming.worktreeDirName(
        slug: slug, timestamp: timestamp, collisionSuffix: suffix
      )
      let worktreePath = (worktreeBase as NSString).appendingPathComponent(dirName)

      do {
        try git.createWorktree(
          repoPath: repo,
          newBranch: branchName,
          baseBranch: baseBranch,
          destinationPath: worktreePath,
          initSubmodules: hasSubmodules,
          symlinkBuildArtifacts: hasSubmodules
        )
        return Prepared(repoRoot: repo, branchName: branchName, worktreePath: worktreePath)
      } catch GitService.GitError.destinationAlreadyExists,
              GitService.GitError.worktreeCreationFailed,
              GitService.GitError.branchCreationFailed {
        continue
      } catch {
        throw ScheduledTaskExecutorError.worktreeCreationFailed(error.localizedDescription)
      }
    }
    throw ScheduledTaskExecutorError.branchCollisionExhausted
  }

  private func makeSession(task: ScheduledTaskRecord, prepared: Prepared, firedAt: Date) -> ClaudeSession {
    let title = "\(task.name) — \(ScheduledTaskNaming.titleTimestamp(firedAt))"
    return ClaudeSession(
      id: UUID().uuidString,
      title: title,
      projectPath: prepared.worktreePath,
      workingDirectory: prepared.worktreePath,
      lastModified: firedAt,
      filePath: nil,
      isNewSession: true,
      tenvySessionId: UUID().uuidString
    )
  }

  private func insertSessionRecord(
    task: ScheduledTaskRecord,
    session: ClaudeSession,
    prepared: Prepared,
    firedAt: Date
  ) throws {
    let permissionJSON = SessionRecord.encode(task.decodedPermissionSettings)
    let record = SessionRecord(
      tenvySessionId: session.tenvySessionId,
      workingDirectory: prepared.worktreePath,
      projectPath: prepared.worktreePath,
      title: session.title,
      branchName: prepared.branchName,
      worktreePath: prepared.worktreePath,
      isPlainTerminal: false,
      isActive: true,
      createdAt: firedAt,
      lastModifiedAt: firedAt,
      permissionSettings: permissionJSON,
      scheduledTaskId: task.id
    )
    try appModel.sessionStore.insertSession(record)
  }

  private func computeNextRun(task: ScheduledTaskRecord, from anchor: Date) -> Date {
    guard let freq = task.resolvedFrequency else {
      // Defensive fallback — should not happen for well-formed records.
      return anchor.addingTimeInterval(3600)
    }
    return freq.nextRunAt(createdAt: task.createdAt, from: anchor)
  }

  // MARK: - Prompt resolution

  /// Resolves the prompt content for this firing. Text prompts are returned as-is.
  /// File prompts are re-read each time (size-capped). Failures throw an executor error.
  private func resolvePromptText(task: ScheduledTaskRecord) throws -> String {
    switch task.resolvedPromptKind {
    case .text:
      return task.promptText ?? ""
    case .file:
      return try readPromptFile(path: task.promptFilePath ?? "")
    case nil:
      return task.promptText ?? ""
    }
  }

  private func readPromptFile(path: String) throws -> String {
    guard !path.isEmpty else {
      throw ScheduledTaskExecutorError.promptFileMissing(path: path)
    }
    let fm = FileManager.default
    let resolved = (path as NSString).expandingTildeInPath
    guard fm.fileExists(atPath: resolved) else {
      throw ScheduledTaskExecutorError.promptFileMissing(path: resolved)
    }
    let attrs = try? fm.attributesOfItem(atPath: resolved)
    if let size = attrs?[.size] as? Int, size > Self.maxPromptFileSize {
      throw ScheduledTaskExecutorError.promptFileTooLarge(path: resolved, size: size)
    }
    do {
      return try String(contentsOfFile: resolved, encoding: .utf8)
    } catch {
      throw ScheduledTaskExecutorError.promptFileUnreadable(
        path: resolved, reason: error.localizedDescription
      )
    }
  }

  // MARK: - Window opening

  private func openBackgroundWindow(for session: ClaudeSession, initialPrompt: String) {
    let newVM = ContentViewModel(appModel: appModel)
    // `preloadForTransfer` activates the session and sets `selectedSession` — exactly what
    // we need for a fresh spawn (host view is nil; the regular `makeNSView` flow creates one).
    newVM.preloadForTransfer(session: session, hostView: nil, isPlainTerminal: false)

    // Stash the prompt before the terminal launches. `ClaudeSessionTerminalView.makeNSView`
    // will consume it and append as the trailing `claude` positional argument.
    let trimmed = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      newVM.setInitialPrompt(tenvySessionId: session.tenvySessionId, prompt: trimmed)
    }

    let rootView = ContentView(viewModel: newVM)
      .environment(appModel)
      .databaseContext(.readOnly { AppDatabase.shared.databaseReader })
    let hostingController = NSHostingController(rootView: rootView)

    // Match `handleDragToNewWindow`: start with `.zero` then set the content size after
    // attaching the hosting controller, so the SwiftUI intrinsic size doesn't shrink the
    // window before we've had a chance to override it.
    let window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .visible
    window.isOpaque = false
    window.backgroundColor = .clear
    window.title = session.title
    window.isReleasedWhenClosed = false

    // Inherit size from the first existing app window, falling back to a sane default.
    let preferredSize: NSSize
    if let reference = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet && $0.level == .normal }) {
      preferredSize = reference.frame.size
    } else {
      preferredSize = NSSize(width: 1100, height: 720)
    }
    window.setContentSize(preferredSize)

    // Cascade scheduled windows so they don't fully overlap when multiple fire close
    // together. Position with the FRAME size (which is now correct).
    if let screen = NSScreen.main {
      let visible = screen.visibleFrame
      let size = window.frame.size
      let randomOffset = CGFloat.random(in: -80...80)
      let origin = NSPoint(
        x: visible.midX - size.width / 2 + randomOffset,
        y: visible.midY - size.height / 2 + randomOffset
      )
      window.setFrameOrigin(origin)
    }

    // Background: orderFront makes the window visible without making it the key window or
    // activating the app. The user's current foreground app keeps focus.
    window.orderFront(nil)
  }

  // MARK: - Overlap rule (§4.4)

  enum OverlapDecision {
    case proceed
    case skip(reason: String)
    case closePriorThenProceed(priorSessionId: String)
  }

  /// Decide what to do given the previous spawned session's state.
  /// - `.proceed` when there is no prior session (or it has clearly ended).
  /// - `.skip` when the prior session is still doing work; the new run is recorded as skipped.
  /// - `.closePriorThenProceed` when the prior session is idle (`waiting`), so we close it and continue.
  func decideOverlap(task: ScheduledTaskRecord) -> OverlapDecision {
    guard let priorTenvyId = task.lastRunSessionId else { return .proceed }

    // Resolve the prior session via activatedSessions (keyed by Claude id / temp UUID).
    let priorSession = appModel.activatedSessions.values.first {
      $0.tenvySessionId == priorTenvyId
    }
    guard let prior = priorSession else {
      // Prior session is no longer active (window closed, process exited) → proceed.
      return .proceed
    }

    let hookState = appModel.runtimeRegistry.info(for: prior.id).hookState
    switch hookState {
    case .waiting:
      return .closePriorThenProceed(priorSessionId: prior.id)
    case .ended:
      return .proceed
    case .processing, .thinking, .waitingPermission:
      return .skip(reason: "Previous run still active (\(hookState?.rawValue ?? "running"))")
    case .started:
      return .skip(reason: "Previous run is still starting up")
    case nil, .unknown:
      // No hook event observed yet — defensive: treat as still occupying the slot.
      return .skip(reason: "Previous run has not reported an idle state yet")
    }
  }

  private func closePriorSession(sessionId: String) {
    // The standard `WindowDelegate.windowShouldClose` shows a confirmation alert when
    // the window has an active session and a live PID — that would block an automatic
    // close. We bypass it by terminating the process and deactivating the session FIRST,
    // so by the time we call `window.close()` the delegate sees no active session and
    // skips the prompt.
    let runtimeInfo = appModel.runtimeRegistry.info(for: sessionId)
    let pid = runtimeInfo.shellPid > 0 ? runtimeInfo.shellPid : runtimeInfo.pid
    if pid > 0 {
      ProcessManager.shared.terminateProcess(pid: pid)
    }
    appModel.deactivateSession(sessionId)
    if let window = appModel.windowRegistry.window(for: sessionId) {
      window.close()
    }
  }

  // MARK: - Lifecycle event handlers

  private func handleStarted(task: ScheduledTaskRecord) {
    let id = "scheduled-\(task.id)-started-\(Int(Date().timeIntervalSince1970))"
    appModel.notifications.notifyScheduledTaskEvent(
      title: "Scheduled task started",
      body: task.name,
      identifier: id
    )
  }

  private func handleSkipped(task: ScheduledTaskRecord, firedAt: Date, reason: String) {
    let nextRun = computeNextRun(task: task, from: firedAt)
    try? appModel.scheduledTaskStore.markRunSkipped(
      id: task.id, at: firedAt, nextRunAt: nextRun, reason: reason
    )
    let id = "scheduled-\(task.id)-skipped-\(Int(firedAt.timeIntervalSince1970))"
    appModel.notifications.notifyScheduledTaskEvent(
      title: "Scheduled task skipped",
      body: "\(task.name) — \(reason)",
      identifier: id
    )
  }

  // MARK: - Failure handling

  private func handleFailure(task: ScheduledTaskRecord, error: Error, firedAt: Date) {
    let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    try? appModel.scheduledTaskStore.markRunFailed(id: task.id, at: firedAt, reason: reason)
    let id = "scheduled-\(task.id)-failed-\(Int(firedAt.timeIntervalSince1970))"
    appModel.notifications.notifyScheduledTaskEvent(
      title: "Scheduled task failed",
      body: "\(task.name) — \(reason)",
      identifier: id
    )
    #if DEBUG
    print("[ScheduledTaskExecutor] Run failed for \(task.name): \(reason)")
    #endif
  }
}

// MARK: - Supporting types

extension ScheduledTaskExecutor {
  fileprivate struct Prepared {
    let repoRoot: String
    let branchName: String
    let worktreePath: String
  }
}

