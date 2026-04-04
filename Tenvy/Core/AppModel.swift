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

// MARK: - Notification Names

extension Notification.Name {
  /// Posted when user taps notification to open a session in a specific window
  static let openSessionFromNotification = Notification.Name("openSessionFromNotification")

  /// Posted when the user changes the appearance mode in Settings
  static let appearanceModeDidChange = Notification.Name("appearanceModeDidChange")
}

/// Application-level model that owns all services and shared state.
///
/// `AppModel` owns all services via constructor injection (protocol types with
/// live defaults), making it fully testable.
///
/// Inject into the SwiftUI view hierarchy at the app root:
/// ```swift
/// @State private var appModel = AppModel()
/// var body: some Scene {
///     WindowGroup { ContentView().environment(appModel) }
/// }
/// ```
/// Views and per-window ViewModels receive it via `@Environment(AppModel.self)`.
@MainActor
@Observable
final class AppModel {

  // MARK: - Services (injected by protocol)

  let sessionDiscovery: any SessionDiscovery
  let hookMonitor: any HookMonitoring
  let hookSetup: any HookSetup
  let notifications: any SessionNotifying
  let updater: any AppUpdating
  let windowRegistry: any WindowRegistering
  let terminalInput: any TerminalInput

  // MARK: - Runtime state registry (internal infrastructure, not protocol-abstracted)

  let runtimeRegistry: SessionRuntimeRegistry

  // MARK: - Persistent session store (GRDB)

  let sessionStore: SessionStore

  // MARK: - Host View Transfer (cross-window session moves)

  /// Temporary store for GhosttyHostViews being transferred between windows.
  /// Source deposits here; destination picks up.
  @ObservationIgnored
  private var hostViewTransfers: [String: GhosttyHostView] = [:]

  /// Weak references to all ContentViewModels so we can coordinate cross-window transfers.
  @ObservationIgnored
  private var registeredViewModels: [WeakRef<ContentViewModel>] = []

  private struct WeakRef<T: AnyObject> {
    weak var value: T?
  }

  func registerViewModel(_ vm: ContentViewModel) {
    registeredViewModels.removeAll { $0.value == nil }
    registeredViewModels.append(WeakRef(value: vm))
  }

  /// Deposit a host view for cross-window transfer (source calls this).
  func depositForTransfer(terminalId: String, hostView: GhosttyHostView) {
    hostViewTransfers[terminalId] = hostView
  }

  /// Pick up a transferred host view (destination calls this). Removes from store.
  func pickupTransfer(terminalId: String) -> GhosttyHostView? {
    hostViewTransfers.removeValue(forKey: terminalId)
  }

  /// Ask whichever ViewModel owns this session to release it for transfer.
  /// The owning ViewModel deposits its host view on `hostViewTransfers` and
  /// removes the session from its split tree / window.
  func releaseSessionForTransfer(sessionId: String) {
    registeredViewModels.removeAll { $0.value == nil }
    for ref in registeredViewModels {
      guard let vm = ref.value, vm.ownsSession(sessionId) else { continue }
      vm.prepareForTransfer(sessionId: sessionId)
      break
    }
  }

  /// Route a transferred session to whichever ViewModel owns the target session.
  /// The destination ViewModel picks up the host view and inserts into its split tree.
  func mergeTransferredSession(_ session: ClaudeSession, alongside targetSessionId: String, direction: SplitDirection = .right) {
    registeredViewModels.removeAll { $0.value == nil }
    for ref in registeredViewModels {
      guard let vm = ref.value, vm.ownsSession(targetSessionId) else { continue }
      vm.receiveTransferredSession(session, alongside: targetSessionId, direction: direction)
      break
    }
  }

  /// Notify all ViewModels about a hook-event-driven session sync.
  /// Called when a hook event arrives with both `terminalId` and `claudeSessionId`.
  func syncSessionFromHookEvent(terminalId: String, claudeSessionId: String) {
    registeredViewModels.removeAll { $0.value == nil }
    for ref in registeredViewModels {
      ref.value?.syncSessionFromHookEvent(terminalId: terminalId, claudeSessionId: claudeSessionId)
    }
  }

  // MARK: - Session models (observable list of facades)

  /// Stable `ClaudeSessionModel` instances keyed by `terminalId` — allows the
  /// computed `sessionModels` to return the same object for the same session
  /// across re-evaluations, preserving SwiftUI view identity.
  private var sessionModelCache: [String: ClaudeSessionModel] = [:]

  /// All known sessions as observable facades. Accessing this property in a view
  /// body registers observation on `sessionDiscovery.sessions`, so the view
  /// re-renders automatically when sessions are added, removed, or renamed.
  var sessionModels: [ClaudeSessionModel] {
    let current = sessionDiscovery.sessions
    // Evict stale cache entries for sessions that no longer exist
    let currentTerminalIds = Set(current.map { $0.terminalId })
    for key in sessionModelCache.keys where !currentTerminalIds.contains(key) {
      sessionModelCache.removeValue(forKey: key)
    }
    return current.map { session in
      if let cached = sessionModelCache[session.terminalId] {
        // Refresh immutable facts (title, lastModified, etc.) without recreating the object
        cached.updateSession(session)
        return cached
      }
      let model = ClaudeSessionModel(session: session, runtime: runtimeRegistry.info(for: session.id))
      sessionModelCache[session.terminalId] = model
      return model
    }
  }

  // MARK: - Activated sessions

  /// Sessions that have a running terminal process.
  /// Used to prevent duplicate process spawning across windows.
  private(set) var activatedSessions: [String: ClaudeSession] = [:]

  // MARK: - App focus

  /// True when any app window is currently key/active.
  var isWindowActive: Bool = true {
    didSet {
      notifications.isWindowActive = isWindowActive
      if isWindowActive {
        // Clear notification only for the session in the focused window —
        // clearing ALL would wipe the dedup guard for background sessions.
        if let keyWindow = NSApplication.shared.keyWindow,
           let sessionId = windowRegistry.sessionId(for: keyWindow) {
          notifications.clearNotification(for: sessionId)
        }
      }
    }
  }

  // MARK: - Init

  /// Designated init — accepts all services as explicit parameters (no defaults).
  /// Use `AppModel()` (convenience) for the live app; use this overload in tests.
  init(
    sessionDiscovery: any SessionDiscovery,
    hookMonitor: any HookMonitoring,
    hookSetup: any HookSetup,
    notifications: any SessionNotifying,
    updater: any AppUpdating,
    windowRegistry: any WindowRegistering,
    terminalInput: any TerminalInput,
    runtimeRegistry: SessionRuntimeRegistry,
    sessionStore: SessionStore
  ) {
    self.sessionDiscovery = sessionDiscovery
    self.hookMonitor = hookMonitor
    self.hookSetup = hookSetup
    self.notifications = notifications
    self.updater = updater
    self.windowRegistry = windowRegistry
    self.terminalInput = terminalInput
    self.runtimeRegistry = runtimeRegistry
    self.sessionStore = sessionStore

    // Inject session store into discovery service for DB upserts
    if let manager = sessionDiscovery as? SessionManager {
      manager.sessionStore = sessionStore
    }

    wireCallbacks()
    setupWindowObservers()
  }

  /// Convenience live-app init. All expressions here run on `@MainActor` because the
  /// class is `@MainActor`, so constructing service instances is safe.
  convenience init() {
    self.init(
      sessionDiscovery: SessionManager(),
      hookMonitor: HookEventService(),
      hookSetup: HookInstallationService(),
      notifications: NotificationService(),
      updater: UpdateService(),
      windowRegistry: WindowSessionRegistry(),
      terminalInput: TerminalRegistry(),
      runtimeRegistry: SessionRuntimeRegistry(),
      sessionStore: SessionStore(database: .shared)
    )
  }

  // MARK: - Session lifecycle

  /// Register a session as having an active terminal process.
  func activateSession(_ session: ClaudeSession) {
    if activatedSessions[session.id] == nil {
      activatedSessions[session.id] = session
    }
  }

  /// Remove a session from the activated set (terminal closed or session terminated).
  /// Also resets the runtime info so the sidebar no longer shows stale CPU/MEM/PID data.
  func deactivateSession(_ sessionId: String) {
    // Find the terminalId for DB update — check activated sessions first
    let terminalId = activatedSessions[sessionId]?.terminalId ?? sessionId
    try? sessionStore.deactivateSession(terminalId: terminalId)

    // Clean up per-session settings file
    SessionSettingsFileManager.removeSettingsFile(terminalId: terminalId)

    activatedSessions.removeValue(forKey: sessionId)
    runtimeRegistry.info(for: sessionId).reset()
  }

  /// True if a session currently has a running terminal.
  func isSessionActivated(_ sessionId: String) -> Bool {
    activatedSessions[sessionId] != nil
  }

  /// Mark a session as activated in the runtime registry (filters stale hook events).
  func markSessionActivated(_ sessionId: String) {
    runtimeRegistry.markSessionActivated(sessionId)
  }

  /// Start tracking a session for hook detection (called when terminal starts).
  func trackSessionForHooks(_ sessionId: String) {
    hookSetup.trackSession(sessionId)
  }

  /// Open a session by ID (called from notification tap or openSessionFromNotification).
  func openSession(sessionId: String) {
    guard let session = activatedSessions[sessionId]
            ?? sessionDiscovery.sessions.first(where: { $0.id == sessionId })
    else { return }

    if let window = windowRegistry.window(for: sessionId) {
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    } else if let mainWindow = NSApplication.shared.mainWindow
                ?? NSApplication.shared.windows.first {
      mainWindow.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      windowRegistry.pendingSessionForNewTab = session
      NotificationCenter.default.post(name: .openSessionFromNotification, object: session)
    }
  }

  // MARK: - Private wiring

  /// Resolve git branches for all known sessions.
  /// Reads `.git/HEAD` directly — no subprocess, safe with Ghostty.
  func refreshGitBranches() {
    for session in sessionDiscovery.sessions {
      let info = runtimeRegistry.info(for: session.id)
      let branch = GitBranchService.currentBranch(at: session.workingDirectory)
      if info.gitBranch != branch {
        info.gitBranch = branch
      }
    }
    // Also refresh for activated sessions not yet in sessionManager
    for (sessionId, session) in activatedSessions {
      let info = runtimeRegistry.info(for: sessionId)
      let branch = GitBranchService.currentBranch(at: session.workingDirectory)
      if info.gitBranch != branch {
        info.gitBranch = branch
      }
    }
  }

  private func wireCallbacks() {
    hookMonitor.onStateChange = { [weak self] sessionId, hookState, tool, message, eventTime, terminalId in
      Task { @MainActor in
        guard let self else { return }

        // Sync FIRST: swap temp UUID → real Claude session ID if needed.
        // This ensures runtimeRegistry and notifications use the correct ID.
        if let terminalId {
          self.syncSessionFromHookEvent(terminalId: terminalId, claudeSessionId: sessionId)
        }

        // Now update in-memory runtime state — after sync, session.id matches sessionId
        self.runtimeRegistry.updateHookState(for: sessionId, state: hookState, tool: tool, eventTime: eventTime)
        self.hookSetup.receivedHookEvent(for: sessionId)

        // Map claudeSessionId → terminalId in DB (one-time per session).
        // Hook state is kept in-memory only (runtimeRegistry) — writing it to DB
        // on every event caused a cascade of @Query refetches that saturated I/O.
        if let terminalId {
          try? self.sessionStore.mapClaudeSessionId(
            terminalId: terminalId,
            claudeSessionId: sessionId
          )
        }

        if hookState == .waiting || hookState == .waitingPermission {
          let sessionName = self.activatedSessions[sessionId]?.title ?? ""
          let isPermission = hookState == .waitingPermission
          self.notifications.notifyWaitingForInput(
            sessionId: sessionId,
            sessionName: sessionName,
            isPermissionRequest: isPermission,
            permissionMessage: message
          )
        } else {
          self.notifications.clearNotification(for: sessionId)
        }
      }
    }

    notifications.windowRegistering = windowRegistry
    notifications.onOpenSession = { [weak self] sessionId in
      Task { @MainActor in self?.openSession(sessionId: sessionId) }
    }

    notifications.onPermissionResponse = { [weak self] sessionId, response in
      Task { @MainActor in self?.terminalInput.sendPermissionResponse(to: sessionId, response: response) }
    }

    notifications.onClearWaitingPermission = { [weak self] sessionId in
      Task { @MainActor in
        self?.runtimeRegistry.updateHookState(for: sessionId, state: .waiting, eventTime: Date())
      }
    }

    hookMonitor.startMonitoring()
  }

  /// Restart sessions that are safely idle (waiting for user input, not actively working).
  /// Called after appearance mode changes so the new Claude CLI theme takes effect immediately.
  func restartWaitingSessions() {
    for sessionId in activatedSessions.keys {
      let info = runtimeRegistry.info(for: sessionId)
      let isWaiting = info.hookState == .waiting
        || (info.hookState == nil && info.state == .waitingForInput)
      let isBusy = info.hookState == .processing
        || info.hookState == .thinking
        || info.hookState == .waitingPermission
      guard isWaiting && !isBusy else { continue }
      terminalInput.restartSession(for: sessionId)
    }
  }

  private func setupWindowObservers() {
    NotificationCenter.default.addObserver(
      forName: .appearanceModeDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor [self] in self.restartWaitingSessions() }
    }

    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor [self] in self.isWindowActive = true }
    }

    NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor [self] in self.isWindowActive = false }
    }
  }
}
