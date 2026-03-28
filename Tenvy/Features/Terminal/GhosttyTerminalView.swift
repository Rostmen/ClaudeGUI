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
///
/// Mirrors the interface of `TerminalContentView` so `TerminalView` can swap
/// between SwiftTerm and Ghostty without changing callers.
struct GhosttyTerminalView: NSViewRepresentable {
  let session: ClaudeSession?
  let isSelected: Bool
  let onStateChange: ((SessionMonitorInfo) -> Void)?
  let onShellStart: ((pid_t) -> Void)?
  let onSessionActivated: ((String) -> Void)?
  let onRegisterForInput: ((GhosttyInputProxy, String) -> Void)?
  let onUnregisterForInput: ((String) -> Void)?
  @Environment(\.colorScheme) private var colorScheme

  func makeNSView(context: Context) -> GhosttyHostView {
    let hostView = GhosttyHostView()
    hostView.setup(
      session: session,
      onStateChange: onStateChange,
      onShellStart: onShellStart,
      onSessionActivated: onSessionActivated,
      onRegisterForInput: onRegisterForInput,
      onUnregisterForInput: onUnregisterForInput
    )
    if isSelected {
      DispatchQueue.main.async { hostView.becomeFirstResponder() }
    }
    return hostView
  }

  func updateNSView(_ nsView: GhosttyHostView, context: Context) {
    nsView.onStateChange = onStateChange

    // Sync Ghostty appearance when color scheme changes
    if context.coordinator.lastColorScheme != colorScheme {
      context.coordinator.lastColorScheme = colorScheme
      GhosttyEmbedApp.shared.applyAppearance(isDark: colorScheme == .dark)
    }

    if isSelected {
      DispatchQueue.main.async {
        if nsView.window?.firstResponder !== nsView.surfaceViewIfReady {
          nsView.surfaceViewIfReady?.window?.makeFirstResponder(nsView.surfaceViewIfReady)
        }
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

  var onStateChange: ((SessionMonitorInfo) -> Void)?
  private var onShellStart: ((pid_t) -> Void)?
  private var onSessionActivated: ((String) -> Void)?
  private var onRegisterForInput: ((GhosttyInputProxy, String) -> Void)?
  private var onUnregisterForInput: ((String) -> Void)?

  var surfaceViewIfReady: NSView? { surface?.nsView }

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
    onUnregisterForInput: ((String) -> Void)?
  ) {
    self.sessionId = session?.id
    self.isNewSession = session?.isNewSession ?? false
    self.onStateChange = onStateChange
    self.onShellStart = onShellStart
    self.onSessionActivated = onSessionActivated
    self.onRegisterForInput = onRegisterForInput
    self.onUnregisterForInput = onUnregisterForInput

    let claudePath = ClaudePathResolver.findClaudePath()
    var args: [String] = []
    if let session = session, !session.isNewSession {
      args = ["--resume", session.id]
    }

    let command = ([claudePath] + args).joined(separator: " ")
    let workingDirectory = session?.workingDirectory ?? NSHomeDirectory()
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
    NSLayoutConstraint.activate([
      surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
      surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
      surfaceView.topAnchor.constraint(equalTo: topAnchor),
      surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    // Notify callers once the process starts (small delay for PTY fork)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.startMonitoring()
    }
  }

  private func startMonitoring() {
    // Find claude's PID from the process tree
    // Ghostty forks its own shell; we search for claude in that tree
    guard let sid = sessionId ?? (isNewSession ? nil : sessionId) else {
      startMonitoringWithoutSessionId()
      return
    }
    startMonitoringWithSessionId(sid)
  }

  private func startMonitoringWithoutSessionId() {
    // For new sessions we don't have the ID yet; monitor without session filter
    startMonitorWithKnownPID(sessionId: nil)
  }

  private func startMonitoringWithSessionId(_ sid: String) {
    startMonitorWithKnownPID(sessionId: sid)
  }

  private func startMonitorWithKnownPID(sessionId: String?) {
    // We don't have a direct PID handle from Ghostty.
    // Use a dummy PID of 0 so the monitor falls back to process-tree search.
    // The SessionStateMonitor will find claude via ProcessPoller.
    let pid: pid_t = 0
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
    if let sid = sessionId {
      let unregister = onUnregisterForInput
      Task { @MainActor in unregister?(sid) }
    }
  }
}
