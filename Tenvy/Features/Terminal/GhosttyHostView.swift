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
///
/// This is a generic terminal host — it handles surface lifecycle, focus, layout,
/// and process monitoring. It does NOT know about Claude sessions, plain terminals,
/// or context menu contents. The owning view provides:
/// - `onAction`: callback for upstream events (monitoring, focus)
/// - `contextMenuProvider`: closure that returns the menu to show on right-click
final class GhosttyHostView: NSView {
  private(set) var surface: GhosttyEmbedSurface?
  private var stateMonitor: SessionStateMonitor?
  private var registeredPID: pid_t = 0
  private var sessionId: String?
  private var isNewSession: Bool = false
  private var launchScriptPath: String?
  private var windowObservation: NSKeyValueObservation?
  private var rightClickMonitor: Any?

  /// Upstream action handler — set by the owning view.
  var onAction: (TerminalAction) -> Void = { _ in }

  /// Called on right-click to build the context menu.
  /// The owning view sets this to provide its own menu.
  /// If nil, Ghostty's default context menu is used.
  var contextMenuProvider: (() -> NSMenu)?

  /// Retains the current menu action target while the context menu is open.
  var menuTarget: AnyObject?

  var surfaceViewIfReady: NSView? { surface?.nsView }

  /// Snapshot of the terminal content for drag previews.
  var snapshotImage: NSImage? { surface?.asImage }

  /// Set to true before adding to a window so `viewDidMoveToWindow` transfers focus immediately.
  var pendingFocus: Bool = false

  func makeFocused() {
    surface?.makeFocused()
  }

  /// Tears down the surface so Ghostty's C layer stops accessing it.
  /// Removes the surface view from the hierarchy, stops monitoring, and removes event monitors.
  /// The caller must keep `self` alive briefly (e.g. via `DispatchQueue.main.async`)
  /// so that `ghostty_surface_free` (scheduled in `Surface.deinit`) runs before the
  /// `SurfaceView` is deallocated — otherwise the C layer's userdata pointer dangles.
  func close() {
    stateMonitor?.stop()
    stateMonitor = nil
    if let monitor = rightClickMonitor {
      NSEvent.removeMonitor(monitor)
      rightClickMonitor = nil
    }
    windowObservation?.invalidate()
    windowObservation = nil
    surface?.nsView.removeFromSuperview()
  }

  /// Resets the terminal (clears screen, resets escape state).
  func resetTerminal() {
    surface?.resetTerminal()
  }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }

  override func layout() {
    super.layout()
    surface?.notifyResize(bounds.size)
  }

  // MARK: - Surface Setup

  /// Creates the Ghostty terminal surface with the given launch command.
  /// - Parameter terminalId: Passed to `TerminalEnvironment.build()` to set `TENVY_TERMINAL_ID`.
  ///   Pass nil for plain terminals (they don't need hook event mapping).
  func setupSurface(
    launch: (executable: String, args: [String]),
    workingDirectory: String,
    terminalId: String? = nil,
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

    let envVars = TerminalEnvironment.build(terminalId: terminalId).reduce(into: [String: String]()) { dict, pair in
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

    // Take over file drag handling from SurfaceView so we can notify SwiftUI
    // about drag enter/exit (for header highlighting) and focus on drop.
    // SurfaceView registers for [.string, .fileURL, .URL] in its init —
    // unregister those types so GhosttyHostView receives drags instead.
    surfaceView.unregisterDraggedTypes()
    registerForDraggedTypes([.string, .fileURL, .URL])

    _ = surfaceView.resignFirstResponder()
    NSLayoutConstraint.activate([
      surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
      surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
      surfaceView.topAnchor.constraint(equalTo: topAnchor),
      surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    // Intercept right-click to show the owning view's context menu.
    rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
      guard let self,
            let surfaceView = self.surface?.nsView,
            let provider = self.contextMenuProvider,
            surfaceView.window == event.window else { return event }

      let locationInSurface = surfaceView.convert(event.locationInWindow, from: nil)
      guard surfaceView.bounds.contains(locationInSurface) else { return event }

      NSMenu.popUpContextMenu(provider(), with: event, for: surfaceView)
      return nil
    }
  }

  // MARK: - Monitoring Setup (Claude sessions only)

  /// Starts process monitoring and session registration.
  /// Call after `setupSurface`. Not needed for plain terminals.
  func setupMonitoring(sessionId: String?, isNewSession: Bool) {
    self.sessionId = sessionId
    self.isNewSession = isNewSession

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

    // Pass a closure that queries Ghostty's PTY foreground PID on each poll.
    // This is the exact process we launched — no process-tree scanning needed.
    let monitor = SessionStateMonitor(pidProvider: { [weak self] in
      self?.surface?.foregroundPid ?? 0
    })
    monitor.onStateChange = { [weak self] info in
      self?.onAction(.stateChanged(info: info))
    }
    stateMonitor = monitor
    monitor.start()
  }

  // MARK: - Drag Destination (file drops)

  private static let fileDragTypes: Set<NSPasteboard.PasteboardType> = [.fileURL, .URL]

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard let types = sender.draggingPasteboard.types,
          !Set(types).isDisjoint(with: Self.fileDragTypes) else { return .copy }
    onAction(.fileDragEntered)
    return .copy
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    onAction(.fileDragExited)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    onAction(.fileDragExited)

    let pb = sender.draggingPasteboard

    // Match Ghostty's SurfaceView.performDragOperation logic:
    // URLs first, then file URLs, then plain strings.
    let content: String?
    if let url = pb.string(forType: .URL) {
      content = Self.shellEscape(url)
    } else if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
      let fileURLs = urls.filter(\.isFileURL)
      if !fileURLs.isEmpty {
        onAction(.fileDropped(urls: fileURLs))
      }
      content = urls
        .map { $0.isFileURL ? Self.shellEscape($0.path) : Self.shellEscape($0.absoluteString) }
        .joined(separator: " ")
    } else if let str = pb.string(forType: .string) {
      content = str
    } else {
      content = nil
    }

    if let content {
      surface?.sendText(content)
      return true
    }
    return false
  }

  /// Escapes shell-sensitive characters for safe insertion into a terminal.
  private static let escapeCharacters = "\\ ()[]{}<>\"'`!#$&;|*?\t"
  static func shellEscape(_ str: String) -> String {
    var result = str
    for char in escapeCharacters {
      result = result.replacingOccurrences(of: String(char), with: "\\\(char)")
    }
    return result
  }

  deinit {
    stateMonitor?.stop()
    windowObservation?.invalidate()
    if let monitor = rightClickMonitor { NSEvent.removeMonitor(monitor) }
    if let sid = sessionId {
      let action = onAction
      Task { @MainActor in action(.inputUnregistered(sessionId: sid)) }
    }
    if let path = launchScriptPath {
      try? FileManager.default.removeItem(atPath: path)
    }
  }
}
