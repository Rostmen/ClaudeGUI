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
import AppKit
import GhosttyEmbed

/// SwiftUI wrapper for a Ghostty terminal surface.
struct GhosttyTerminalView: NSViewRepresentable {
  let session: ClaudeSession?
  let isSelected: Bool
  let onStateChange: ((SessionMonitorInfo) -> Void)?
  let onShellStart: ((pid_t) -> Void)?
  let onSessionActivated: ((String) -> Void)?
  let onRegisterForInput: ((GhosttyInputProxy, String) -> Void)?
  let onUnregisterForInput: ((String) -> Void)?
  /// Called when the user requests a split from Ghostty's context menu.
  let onSplitRequested: ((SplitDirection) -> Void)?
  /// Called when this terminal's surface gains keyboard focus.
  let onFocusGained: (() -> Void)?
  /// Pre-existing host view to reuse instead of creating a new one.
  /// Prevents process restarts when SwiftUI restructures the view tree (e.g. on split).
  let existingHostView: GhosttyHostView?
  /// Called with the newly created GhosttyHostView so callers can cache it.
  let onHostViewCreated: ((GhosttyHostView) -> Void)?
  @Environment(\.colorScheme) private var colorScheme

  func makeNSView(context: Context) -> GhosttyHostView {
    // Reuse cached view if available — the process is already running.
    if let existing = existingHostView {
      // pendingFocus handled by updateNSView (window is already set on existing views).
      return existing
    }

    let hostView = GhosttyHostView()
    hostView.setup(
      session: session,
      onStateChange: onStateChange,
      onShellStart: onShellStart,
      onSessionActivated: onSessionActivated,
      onRegisterForInput: onRegisterForInput,
      onUnregisterForInput: onUnregisterForInput,
      onSplitRequested: onSplitRequested,
      onFocusGained: onFocusGained
    )
    // Mark for focus so viewDidMoveToWindow() transfers it once the view has a window.
    if isSelected {
      hostView.pendingFocus = true
    }
    onHostViewCreated?(hostView)
    return hostView
  }

  func updateNSView(_ nsView: GhosttyHostView, context: Context) {
    nsView.onStateChange = onStateChange
    nsView.onFocusGained = onFocusGained

    // Sync Ghostty appearance when color scheme changes
    if context.coordinator.lastColorScheme != colorScheme {
      context.coordinator.lastColorScheme = colorScheme
      GhosttyEmbedApp.shared.applyAppearance(isDark: colorScheme == .dark)
    }

    if isSelected {
      // Only transfer focus when the view is already in a window (window != nil).
      // If it isn't yet (new split pane), viewDidMoveToWindow will handle it via pendingFocus.
      if nsView.window != nil {
        DispatchQueue.main.async {
          guard let surfaceView = nsView.surfaceViewIfReady, nsView.window != nil else { return }
          let fr = nsView.window?.firstResponder as? NSView
          if fr == nil || !(fr!.isDescendant(of: surfaceView)) {
            nsView.makeFocused()
          }
        }
      } else {
        nsView.pendingFocus = true
      }
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }
  class Coordinator {
    var lastColorScheme: ColorScheme = .dark
  }
}

// MARK: - GhosttyInputProxy

/// Allows `TerminalRegistry` to send text into a Ghostty terminal surface.
/// Conforms to `TerminalInputSender` so it works with `TerminalRegistry`.
final class GhosttyInputProxy: TerminalInputSender {
  private weak var surface: GhosttyEmbedSurface?

  init(surface: GhosttyEmbedSurface) {
    self.surface = surface
  }

  @MainActor
  func send(txt text: String) {
    surface?.sendText(text)
  }

  @MainActor
  func restartSession() {
    // Ghostty terminal restart is not supported; no-op.
  }
}

// MARK: - GhosttyHostView

/// Thin NSView container that owns the Ghostty `SurfaceView` as a child.
final class GhosttyHostView: NSView {
  private(set) var surface: GhosttyEmbedSurface?
  private var stateMonitor: SessionStateMonitor?
  private var registeredPID: pid_t = 0
  private var sessionId: String?
  private var isNewSession: Bool = false
  private var launchScriptPath: String?
  private var splitObserver: NSObjectProtocol?
  private var windowObservation: NSKeyValueObservation?

  var onStateChange: ((SessionMonitorInfo) -> Void)?
  var onFocusGained: (() -> Void)?
  private var onShellStart: ((pid_t) -> Void)?
  private var onSessionActivated: ((String) -> Void)?
  private var onRegisterForInput: ((GhosttyInputProxy, String) -> Void)?
  private var onUnregisterForInput: ((String) -> Void)?
  private var onSplitRequested: ((SplitDirection) -> Void)?

  var surfaceViewIfReady: NSView? { surface?.nsView }

  /// Set to true before adding to a window so `viewDidMoveToWindow` transfers focus immediately.
  var pendingFocus: Bool = false

  /// Make this terminal's surface the keyboard focus.
  /// Calls `GhosttyEmbedSurface.makeFocused()` which resets Ghostty's internal
  /// focus state before handing first-responder to the surface view.
  func makeFocused() {
    surface?.makeFocused()
  }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }

  override func layout() {
    super.layout()
    surface?.notifyResize(bounds.size)
  }

  func setup(
    session: ClaudeSession?,
    onStateChange: ((SessionMonitorInfo) -> Void)?,
    onShellStart: ((pid_t) -> Void)?,
    onSessionActivated: ((String) -> Void)?,
    onRegisterForInput: ((GhosttyInputProxy, String) -> Void)?,
    onUnregisterForInput: ((String) -> Void)?,
    onSplitRequested: ((SplitDirection) -> Void)?,
    onFocusGained: (() -> Void)?
  ) {
    self.sessionId = session?.id
    self.isNewSession = session?.isNewSession ?? false
    self.onStateChange = onStateChange
    self.onShellStart = onShellStart
    self.onSessionActivated = onSessionActivated
    self.onRegisterForInput = onRegisterForInput
    self.onUnregisterForInput = onUnregisterForInput
    self.onSplitRequested = onSplitRequested
    self.onFocusGained = onFocusGained

    let claudePath = ClaudePathResolver.findClaudePath()
    var args: [String] = []
    if let session = session, !session.isNewSession {
      args = ["--resume", session.id]
    }

    let workingDirectory = session?.workingDirectory ?? NSHomeDirectory()

    // Build launch via login shell (same as SwiftTerm) so ~/.zprofile is sourced
    // and PATH includes Homebrew, NVM, etc. Write the shell script to a temp file
    // to avoid quoting issues with Ghostty's command string parser.
    let launch = TerminalEnvironment.shellArgs(executable: claudePath, args: args, currentDirectory: workingDirectory)
    let scriptContent = launch.args.last ?? ""
    let scriptPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("tenvy-\(UUID().uuidString).sh")
    try? scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
    launchScriptPath = scriptPath
    let command = "\(launch.executable) -l \(scriptPath)"

    let envVars = TerminalEnvironment.build().reduce(into: [String: String]()) { dict, pair in
      let parts = pair.split(separator: "=", maxSplits: 1)
      if parts.count == 2 { dict[String(parts[0])] = String(parts[1]) }
    }

    guard let embedSurface = GhosttyEmbedApp.shared.makeSurface(
      command: command,
      workingDirectory: workingDirectory,
      environment: envVars
    ) else { return }

    self.surface = embedSurface
    let surfaceView = embedSurface.nsView
    surfaceView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(surfaceView)

    // Ghostty SurfaceView defaults focused=true. Reset to false so that
    // performKeyEquivalent doesn't route paste/shortcuts to a non-active
    // pane in split mode. Focus is granted only via makeFocused() below.
    _ = surfaceView.resignFirstResponder()
    NSLayoutConstraint.activate([
      surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
      surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
      surfaceView.topAnchor.constraint(equalTo: topAnchor),
      surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    // Listen for split requests from Ghostty's context menu.
    // Map GhosttyEmbedSplitDirection → SplitDirection here so callers stay decoupled from GhosttyEmbed types.
    splitObserver = embedSurface.onSplitRequest { [weak self] direction in
      let appDirection: SplitDirection
      switch direction {
      case .right: appDirection = .right
      case .down:  appDirection = .down
      case .left:  appDirection = .left
      case .up:    appDirection = .up
      }
      self?.onSplitRequested?(appDirection)
    }

    // Notify callers once the process starts (small delay for PTY fork)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.startMonitoring()
    }
  }

  // Called when the view enters a window — reliable point where `window` is non-nil.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    windowObservation?.invalidate()
    windowObservation = nil
    guard let window = window else { return }

    windowObservation = window.observe(\.firstResponder) { [weak self] _, _ in
      self?.checkFocus()
    }

    // If focus was requested before the view was in a window, honour it now.
    // Deferred by one run loop tick so that Ghostty's own viewDidMoveToWindow
    // (fired on the child surfaceView after ours) doesn't reset the focus state.
    if pendingFocus {
      pendingFocus = false
      DispatchQueue.main.async { [weak self] in
        self?.makeFocused()
      }
    }
  }

  private func checkFocus() {
    guard let surfaceView = surface?.nsView,
          let responder = window?.firstResponder as? NSView else { return }
    if responder.isDescendant(of: surfaceView) {
      onFocusGained?()
    }
  }

  private func startMonitoring() {
    // For new sessions the session ID is a temporary placeholder that never appears
    // in the process args — pass nil so the monitor matches by PID/ancestry only.
    // For resumed sessions pass the real session ID for precise matching.
    let monitorSessionId: String? = isNewSession ? nil : sessionId

    // Use ghostty_surface_foreground_pid to get the exact PTY foreground PID for
    // this specific terminal surface. Since the launch script uses `exec claude`,
    // the shell has already been replaced by the time we reach here (0.5 s delay).
    // This eliminates ambiguity when multiple sessions are open in the same folder —
    // each surface reports its own PTY's foreground PID rather than a shared ancestor.
    let ptyPid: pid_t = surface?.foregroundPid ?? 0
    startMonitorWithPID(ptyPid, sessionId: monitorSessionId)
  }

  private func startMonitorWithPID(_ pid: pid_t, sessionId: String?) {
    registeredPID = pid

    if let sid = sessionId {
      onSessionActivated?(sid)
      if let surface = surface {
        let proxy = GhosttyInputProxy(surface: surface)
        onRegisterForInput?(proxy, sid)
      }
    }

    let monitor = SessionStateMonitor(processPID: pid, sessionId: sessionId)
    monitor.onStateChange = { [weak self] info in
      self?.onStateChange?(info)
    }
    stateMonitor = monitor
    monitor.start()
  }

  deinit {
    stateMonitor?.stop()
    windowObservation?.invalidate()
    if let obs = splitObserver { NotificationCenter.default.removeObserver(obs) }
    if let sid = sessionId {
      let unregister = onUnregisterForInput
      Task { @MainActor in unregister?(sid) }
    }
    if let path = launchScriptPath {
      try? FileManager.default.removeItem(atPath: path)
    }
  }
}
