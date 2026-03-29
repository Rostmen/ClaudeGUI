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
import GhosttyEmbed

/// Thin NSView container that owns the Ghostty `SurfaceView` as a child.
/// Shared by both `GhosttyTerminalView` (Claude) and `GhosttyPlainTerminalView` (shell).
/// Use `setupSurface` for the terminal surface, then optionally `setupMonitoring` for Claude sessions.
final class GhosttyHostView: NSView {
  private(set) var surface: GhosttyEmbedSurface?
  private var stateMonitor: SessionStateMonitor?
  private var registeredPID: pid_t = 0
  private var sessionId: String?
  private var isNewSession: Bool = false
  private var launchScriptPath: String?
  private var splitObserver: NSObjectProtocol?
  private var windowObservation: NSKeyValueObservation?

  /// Single action handler for all terminal events.
  var onAction: (TerminalAction) -> Void = { _ in }

  var surfaceViewIfReady: NSView? { surface?.nsView }

  /// Set to true before adding to a window so `viewDidMoveToWindow` transfers focus immediately.
  var pendingFocus: Bool = false

  func makeFocused() {
    surface?.makeFocused()
  }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }

  override func layout() {
    super.layout()
    surface?.notifyResize(bounds.size)
  }

  // MARK: - Surface Setup

  /// Creates the Ghostty terminal surface with the given launch command.
  /// Handles surface creation, layout, focus reset, and split request forwarding.
  func setupSurface(
    launch: (executable: String, args: [String]),
    workingDirectory: String,
    onAction: @escaping (TerminalAction) -> Void
  ) {
    self.onAction = onAction

    // Write launch script to temp file to avoid quoting issues with Ghostty's command parser.
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
    // pane in split mode. Focus is granted only via makeFocused().
    _ = surfaceView.resignFirstResponder()
    NSLayoutConstraint.activate([
      surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
      surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
      surfaceView.topAnchor.constraint(equalTo: topAnchor),
      surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    // Forward split requests from Ghostty's context menu.
    splitObserver = embedSurface.onSplitRequest { [weak self] direction in
      let appDirection: SplitDirection
      switch direction {
      case .right: appDirection = .right
      case .down:  appDirection = .down
      case .left:  appDirection = .left
      case .up:    appDirection = .up
      }
      self?.onAction(.splitRequested(direction: appDirection))
    }
  }

  // MARK: - Monitoring Setup (Claude sessions only)

  /// Starts process monitoring and session registration.
  /// Call after `setupSurface`. Not needed for plain terminals.
  func setupMonitoring(sessionId: String?, isNewSession: Bool) {
    self.sessionId = sessionId
    self.isNewSession = isNewSession

    // Delay for PTY fork to complete
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.startMonitoring()
    }
  }

  // MARK: - Window & Focus

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    windowObservation?.invalidate()
    windowObservation = nil
    guard let window = window else { return }

    windowObservation = window.observe(\.firstResponder) { [weak self] _, _ in
      self?.checkFocus()
    }

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
      onAction(.focusGained)
    }
  }

  // MARK: - Process Monitoring

  private func startMonitoring() {
    let monitorSessionId: String? = isNewSession ? nil : sessionId
    let ptyPid: pid_t = surface?.foregroundPid ?? 0
    registeredPID = ptyPid

    if let sid = monitorSessionId {
      onAction(.sessionActivated(id: sid))
      if let surface = surface {
        let proxy = GhosttyInputProxy(surface: surface)
        onAction(.inputReady(proxy: proxy, sessionId: sid))
      }
    }

    let monitor = SessionStateMonitor(processPID: ptyPid, sessionId: monitorSessionId)
    monitor.onStateChange = { [weak self] info in
      self?.onAction(.stateChanged(info: info))
    }
    stateMonitor = monitor
    monitor.start()
  }

  deinit {
    stateMonitor?.stop()
    windowObservation?.invalidate()
    if let obs = splitObserver { NotificationCenter.default.removeObserver(obs) }
    if let sid = sessionId {
      let action = onAction
      Task { @MainActor in action(.inputUnregistered(sessionId: sid)) }
    }
    if let path = launchScriptPath {
      try? FileManager.default.removeItem(atPath: path)
    }
  }
}
