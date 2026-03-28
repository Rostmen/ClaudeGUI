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
import SwiftTerm
import GhosttyEmbed

// MARK: - Split Direction

/// Direction in which a new split pane should appear.
enum SplitDirection {
  case right, down, left, up
  var isVertical: Bool { self == .down || self == .up }
  var isReversed: Bool { self == .left || self == .up }
}

struct TerminalView: View {
  let session: ClaudeSession?
  let isSelected: Bool
  let onStateChange: ((SessionMonitorInfo) -> Void)?
  let onShellStart: ((pid_t) -> Void)?
  let onSessionActivated: ((String) -> Void)?
  let onRegisterForInput: ((any TerminalInputSender, String) -> Void)?
  let onUnregisterForInput: ((String) -> Void)?
  /// Called when the user requests a split from Ghostty's context menu (Ghostty mode only).
  let onSplitRequested: ((SplitDirection) -> Void)?
  /// Called when this terminal's surface gains keyboard focus (Ghostty mode only).
  let onFocusGained: (() -> Void)?
  /// Pre-existing GhosttyHostView to reuse (Ghostty mode only). Prevents process restart on split.
  let existingHostView: GhosttyHostView?
  /// Called with the newly created GhosttyHostView so callers can cache it (Ghostty mode only).
  let onHostViewCreated: ((GhosttyHostView) -> Void)?

  init(
    session: ClaudeSession?,
    isSelected: Bool = false,
    onStateChange: ((SessionMonitorInfo) -> Void)? = nil,
    onShellStart: ((pid_t) -> Void)? = nil,
    onSessionActivated: ((String) -> Void)? = nil,
    onRegisterForInput: ((any TerminalInputSender, String) -> Void)? = nil,
    onUnregisterForInput: ((String) -> Void)? = nil,
    onSplitRequested: ((SplitDirection) -> Void)? = nil,
    onFocusGained: (() -> Void)? = nil,
    existingHostView: GhosttyHostView? = nil,
    onHostViewCreated: ((GhosttyHostView) -> Void)? = nil
  ) {
    self.session = session
    self.isSelected = isSelected
    self.onStateChange = onStateChange
    self.onShellStart = onShellStart
    self.onSessionActivated = onSessionActivated
    self.onRegisterForInput = onRegisterForInput
    self.onUnregisterForInput = onUnregisterForInput
    self.onSplitRequested = onSplitRequested
    self.onFocusGained = onFocusGained
    self.existingHostView = existingHostView
    self.onHostViewCreated = onHostViewCreated
  }

  var body: some View {
    let settings = AppSettings.shared
    switch settings.terminalType {
    case .swiftTerm:
      TerminalContentView(
        session: session,
        isSelected: isSelected,
        onStateChange: onStateChange,
        onShellStart: onShellStart,
        onSessionActivated: onSessionActivated,
        onRegisterForInput: { (terminal: DraggableTerminalView, sid) in
          onRegisterForInput?(terminal, sid)
        },
        onUnregisterForInput: onUnregisterForInput,
        onFocusGained: onFocusGained
      )
    case .ghostty:
      GhosttyTerminalView(
        session: session,
        isSelected: isSelected,
        onStateChange: onStateChange,
        onShellStart: onShellStart,
        onSessionActivated: onSessionActivated,
        onRegisterForInput: { (proxy: GhosttyInputProxy, sid) in
          onRegisterForInput?(proxy, sid)
        },
        onUnregisterForInput: onUnregisterForInput,
        onSplitRequested: onSplitRequested.map { handler in
          { (embedDir: GhosttyEmbedSplitDirection) in
            switch embedDir {
            case .right: handler(.right)
            case .down:  handler(.down)
            case .left:  handler(.left)
            case .up:    handler(.up)
            }
          }
        },
        onFocusGained: onFocusGained,
        existingHostView: existingHostView,
        onHostViewCreated: onHostViewCreated
      )
    }
  }
}

struct TerminalContentView: NSViewRepresentable {
  let session: ClaudeSession?
  let isSelected: Bool
  let onStateChange: ((SessionMonitorInfo) -> Void)?
  let onShellStart: ((pid_t) -> Void)?
  let onSessionActivated: ((String) -> Void)?
  let onRegisterForInput: ((DraggableTerminalView, String) -> Void)?
  let onUnregisterForInput: ((String) -> Void)?
  let onFocusGained: (() -> Void)?
  @Environment(\.colorScheme) private var colorScheme

  func makeNSView(context: Context) -> DraggableTerminalView {
    let terminalView = DraggableTerminalView(frame: .zero)
    terminalView.onStateChange = onStateChange
    terminalView.onShellStart = onShellStart
    terminalView.sessionId = session?.id
    terminalView.isNewSession = session?.isNewSession ?? false

    // Wire up activation callbacks via injected closures — no singleton references here.
    terminalView.onSessionActivated = onSessionActivated
    terminalView.onRegisterForInput = onRegisterForInput
    terminalView.onUnregisterForInput = onUnregisterForInput
    terminalView.onFocusGained = onFocusGained

    applyColors(to: terminalView, colorScheme: colorScheme)

    terminalView.wantsLayer = true
    terminalView.layer?.backgroundColor = NSColor.clear.cgColor

    // Configure scroll view for overlay style scrollers (thin, translucent)
    terminalView.configureScrollerStyle()

    terminalView.registerForDraggedTypes([.fileURL])

    context.coordinator.terminalView = terminalView
    context.coordinator.startProcess(in: terminalView, session: session)

    if isSelected {
      DispatchQueue.main.async {
        terminalView.window?.makeFirstResponder(terminalView)
      }
    }

    return terminalView
  }

  func updateNSView(_ nsView: DraggableTerminalView, context: Context) {
    // Always update callbacks and session ID to ensure they use current values
    nsView.onStateChange = onStateChange
    nsView.onShellStart = onShellStart
    nsView.sessionId = session?.id
    nsView.isNewSession = session?.isNewSession ?? false
    nsView.onFocusGained = onFocusGained
    context.coordinator.onStateChange = onStateChange

    // Re-apply colors when color scheme changes
    if context.coordinator.lastColorScheme != colorScheme {
      context.coordinator.lastColorScheme = colorScheme
      applyColors(to: nsView, colorScheme: colorScheme)
    }

    if context.coordinator.currentSessionId != session?.id {
      context.coordinator.currentSessionId = session?.id
      context.coordinator.startProcess(in: nsView, session: session)
    }

    if isSelected {
      DispatchQueue.main.async {
        // Only steal focus if nothing inside this view already has it.
        // This prevents re-renders from overriding user focus in split mode.
        let fr = nsView.window?.firstResponder as? NSView
        if fr == nil || !fr!.isDescendant(of: nsView) {
          nsView.window?.makeFirstResponder(nsView)
        }
      }
    }
  }

  private func applyColors(to terminalView: DraggableTerminalView, colorScheme: ColorScheme) {
    if colorScheme == .dark {
      terminalView.installColors(ClaudeTerminalColors.darkPalette)
      terminalView.nativeBackgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: kWindowOpacity)
      terminalView.nativeForegroundColor = NSColor(calibratedWhite: 1, alpha: 1)
    } else {
      terminalView.installColors(ClaudeTerminalColors.lightPalette)
      terminalView.nativeBackgroundColor = NSColor(red: 1, green: 1, blue: 1, alpha: kWindowOpacity)
      terminalView.nativeForegroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
    }
    // Force SwiftTerm to redraw the existing buffer with the new palette.
    terminalView.setNeedsDisplay(terminalView.bounds)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(currentSessionId: session?.id, onStateChange: onStateChange, colorScheme: colorScheme)
  }

  class Coordinator {
    var currentSessionId: String?
    var terminalView: DraggableTerminalView?
    var onStateChange: ((SessionMonitorInfo) -> Void)?
    var lastColorScheme: ColorScheme

    init(currentSessionId: String?, onStateChange: ((SessionMonitorInfo) -> Void)?, colorScheme: ColorScheme) {
      self.currentSessionId = currentSessionId
      self.onStateChange = onStateChange
      self.lastColorScheme = colorScheme
    }

    func startProcess(in terminalView: DraggableTerminalView, session: ClaudeSession?) {
      let claudePath = ClaudePathResolver.findClaudePath()

      // Build arguments - resume existing session if not new
      var args: [String] = []
      if let session = session, !session.isNewSession {
        args = ["--resume", session.id]
      }

      // Build environment with terminal settings
      let env = TerminalEnvironment.build()

      // Set working directory — passed into the child shell via a `cd` clause so
      // the change is process-local and does not mutate the app-wide cwd.
      let workingDirectory = session?.workingDirectory ?? NSHomeDirectory()
      terminalView.workingDirectory = workingDirectory

      // Launch through a login+interactive shell so ~/.zprofile and ~/.zshrc
      // are sourced. `exec` replaces the shell with claude (same PID).
      let launch = TerminalEnvironment.shellArgs(executable: claudePath, args: args, currentDirectory: workingDirectory)
      terminalView.startProcess(
        executable: launch.executable,
        args: launch.args,
        environment: env,
        execName: "claude"
      )
    }
  }
}

// MARK: - TerminalInputSender conformance for DraggableTerminalView

extension DraggableTerminalView: TerminalInputSender {}

// MARK: - DraggableTerminalView

class DraggableTerminalView: LocalProcessTerminalView {
  var onStateChange: ((SessionMonitorInfo) -> Void)?
  var onShellStart: ((pid_t) -> Void)?
  /// Called when the session is activated (terminal started).
  /// Replaces the direct singleton call so the view is independently testable.
  var onSessionActivated: ((String) -> Void)?
  /// Called to register this terminal for remote input (e.g., notification actions).
  var onRegisterForInput: ((DraggableTerminalView, String) -> Void)?
  /// Called when the view is deallocated to unregister from the terminal input registry.
  var onUnregisterForInput: ((String) -> Void)?
  /// Called when this terminal gains keyboard focus (first responder moves into this view).
  var onFocusGained: (() -> Void)?

  private var windowFocusObservation: NSKeyValueObservation?

  var sessionId: String?
  var isNewSession: Bool = false  // New sessions don't have their ID in process args
  var workingDirectory: String?
  private var currentState: SessionState = .inactive
  private var stateMonitor: SessionStateMonitor?
  private var registeredPID: pid_t = 0
  private var pendingRestart = false

  func startStateMonitoring() {
    // Get the process PID from LocalProcess
    let pid = process.shellPid
    guard pid > 0 else { return }

    // Register process with ProcessManager for cleanup on app termination
    registeredPID = pid
    ProcessManager.shared.registerProcess(pid: pid)

    // Notify that the shell process has started (for tracking shell PID)
    DispatchQueue.main.async { [weak self] in
      self?.onShellStart?(pid)
    }

    // Notify activation via injected callbacks.
    if let sessionId = sessionId {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.onSessionActivated?(sessionId)
        self.onRegisterForInput?(self, sessionId)
      }
    }

    // For new sessions, don't filter by session ID because Claude creates its own ID
    // The process tree descent check is sufficient since we only look at our shell's children
    let monitorSessionId = isNewSession ? nil : sessionId
    stateMonitor = SessionStateMonitor(processPID: pid, sessionId: monitorSessionId)
    stateMonitor?.onStateChange = { [weak self] info in
      self?.setMonitorInfo(info)
    }
    stateMonitor?.start()
  }

  func stopStateMonitoring() {
    stateMonitor?.stop()
    stateMonitor = nil
  }

  /// Named constant documenting why the delay exists — SwiftTerm populates
  /// `shellPid` asynchronously after the PTY fork; this grace period ensures the
  /// PID is available before `startStateMonitoring` reads it.
  private static let processStartupGracePeriod: TimeInterval = 0.5

  // Override dataReceived from LocalProcessDelegate to intercept terminal data.
  // We use the first received byte as the "process is alive" signal.
  override func dataReceived(slice: ArraySlice<UInt8>) {
    super.dataReceived(slice: slice)

    // Start monitoring exactly once, after the process has begun producing output.
    if stateMonitor == nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.processStartupGracePeriod) { [weak self] in
        self?.startStateMonitoring()
      }
    }
  }

  // Override processTerminated from LocalProcessDelegate
  override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
    super.processTerminated(source, exitCode: exitCode)
    stopStateMonitoring()

    // Unregister process from ProcessManager
    if registeredPID > 0 {
      ProcessManager.shared.unregisterProcess(pid: registeredPID)
      registeredPID = 0
    }

    setMonitorInfo(SessionMonitorInfo(state: .inactive, cpu: 0, memory: 0, pid: 0))

    // If a restart was requested, launch now that the old process is confirmed dead.
    if pendingRestart {
      pendingRestart = false
      launchProcess()
    }
  }

  /// Terminate the running process and its children
  func terminateProcess() {
    if registeredPID > 0 {
      ProcessManager.shared.terminateProcess(pid: registeredPID)
      registeredPID = 0
    }
  }

  /// Restart the session — terminates the current process and starts a new one.
  /// The actual relaunch happens in `processTerminated`, once the OS confirms the
  /// process is gone, eliminating the old arbitrary 0.3s delay.
  func restartSession() {
    stopStateMonitoring()
    pendingRestart = true

    if registeredPID > 0 {
      ProcessManager.shared.terminateProcess(pid: registeredPID)
      registeredPID = 0
    }
  }

  /// Shared launch helper used by both `Coordinator.startProcess` and the
  /// `pendingRestart` path in `processTerminated`.
  private func launchProcess() {
    let claudePath = ClaudePathResolver.findClaudePath()

    var args: [String] = []
    if let sessionId = sessionId {
      args = ["--resume", sessionId]
    }

    let env = TerminalEnvironment.build()
    let launch = TerminalEnvironment.shellArgs(
      executable: claudePath,
      args: args,
      currentDirectory: workingDirectory
    )
    startProcess(
      executable: launch.executable,
      args: launch.args,
      environment: env,
      execName: "claude"
    )
  }

  // KVO: observe firstResponder so focus changes between split panes update selectedSession.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    windowFocusObservation?.invalidate()
    windowFocusObservation = nil
    guard let window = window else { return }
    windowFocusObservation = window.observe(\.firstResponder) { [weak self] _, _ in
      self?.checkFocus()
    }
  }

  private func checkFocus() {
    guard let responder = window?.firstResponder as? NSView else { return }
    if responder.isDescendant(of: self) {
      onFocusGained?()
    }
  }

  deinit {
    windowFocusObservation?.invalidate()
    // Unregister from terminal input registry via injected callback
    if let sessionId = sessionId {
      let unregister = onUnregisterForInput
      Task { @MainActor in
        unregister?(sessionId)
      }
    }
    // Ensure process is terminated when view is deallocated
    if registeredPID > 0 {
      ProcessManager.shared.terminateProcess(pid: registeredPID)
    }
  }

  /// Configure the scroll view to use overlay style scrollers (thin, translucent like Terminal.app)
  func configureScrollerStyle() {
    // Find the enclosing scroll view and configure it
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if let scrollView = self.enclosingScrollView {
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false

        // Make scroller knob more visible with a light color
        if let verticalScroller = scrollView.verticalScroller {
          verticalScroller.scrollerStyle = .overlay
        }
      }
    }
  }

  private func setMonitorInfo(_ info: SessionMonitorInfo) {
    currentState = info.state
    DispatchQueue.main.async { [weak self] in
      self?.onStateChange?(info)
    }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
      return .copy
    }
    return []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
      return .copy
    }
    return []
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
      return false
    }

    // Build path string with proper escaping for shell
    let paths = urls.map { url -> String in
      let path = url.path
      // Escape spaces and special characters for shell
      return path.replacingOccurrences(of: " ", with: "\\ ")
        .replacingOccurrences(of: "(", with: "\\(")
        .replacingOccurrences(of: ")", with: "\\)")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\"", with: "\\\"")
    }.joined(separator: " ")

    // Send the path to the terminal
    send(txt: paths)

    return true
  }
}

// MARK: - Session State Monitor (CPU-based like ClaudeCodeMonitor)
// Based on https://github.com/Aura-Technologies-llc/ClaudeCodeMonitor

/// Holds monitoring info: state, CPU usage, memory, and the monitored PID
struct SessionMonitorInfo {
  let state: SessionState
  let cpu: Double
  let memory: UInt64
  let pid: pid_t
}

/// Monitors the CPU/memory of a single session's claude process.
///
/// Instead of running its own `ps` subprocess, it subscribes to the shared
/// `ProcessPoller` actor, which runs one `ps` per 500 ms for all sessions combined.
class SessionStateMonitor {
  let shellPID: pid_t
  let sessionId: String?
  var onStateChange: ((SessionMonitorInfo) -> Void)?

  private let pollerId = UUID()
  private var currentState: SessionState = .inactive
  private var cpuHistory: [Double] = []
  private var stateStartTime: Date = Date()
  private let processStartTime: Date = Date()
  private var claudePID: pid_t = 0

  // Thresholds based on ClaudeCodeMonitor
  private let cpuHighThreshold: Double = 25.0  // CPU > 25% = thinking
  private let cpuLowThreshold: Double = 3.0    // CPU < 3% = idle/waiting
  private let historySize = 3                   // Rolling average window
  private let minRunningTime: TimeInterval = 5  // Min time before state changes
  private let minStateTime: TimeInterval = 2    // Min time in state before transition

  init(processPID: pid_t, sessionId: String? = nil) {
    self.shellPID = processPID
    self.sessionId = sessionId
  }

  func start() {
    let monitorId = pollerId
    let shellPID = self.shellPID
    let sessionId = self.sessionId
    Task {
      await ProcessPoller.shared.subscribe(id: monitorId) { [weak self] snapshot in
        self?.handleSnapshot(snapshot, shellPID: shellPID, sessionId: sessionId)
      }
    }
    emit(.waitingForInput, cpu: 0, memory: 0)
  }

  func stop() {
    let monitorId = pollerId
    Task { await ProcessPoller.shared.unsubscribe(id: monitorId) }
  }

  private func handleSnapshot(_ snapshot: [pid_t: ProcessPoller.ProcessRecord], shellPID: pid_t, sessionId: String?) {
    let pid = ProcessTreeAnalyzer.findClaudeProcess(in: snapshot, shellPID: shellPID, sessionId: sessionId)
    claudePID = pid

    guard pid > 0, let record = snapshot[pid] else {
      emit(.inactive, cpu: 0, memory: 0)
      return
    }

    let cpu = record.cpu
    let memoryBytes = record.memoryKB * 1024

    cpuHistory.append(cpu)
    if cpuHistory.count > historySize { cpuHistory.removeFirst() }

    let avgCPU = cpuHistory.reduce(0, +) / Double(cpuHistory.count)
    let timeSinceStart = Date().timeIntervalSince(processStartTime)
    let timeSinceStateChange = Date().timeIntervalSince(stateStartTime)
    let newState = deriveState(avgCPU: avgCPU, timeSinceStart: timeSinceStart, timeSinceStateChange: timeSinceStateChange)

    if newState != currentState {
      emit(newState, cpu: avgCPU, memory: memoryBytes)
    } else {
      reportStats(cpu: avgCPU, memory: memoryBytes)
    }
  }

  private func deriveState(avgCPU: Double, timeSinceStart: TimeInterval, timeSinceStateChange: TimeInterval) -> SessionState {
    switch currentState {
    case .inactive, .waitingForInput:
      if avgCPU > cpuHighThreshold && timeSinceStart > minRunningTime { return .thinking }
      return .waitingForInput
    case .thinking:
      if avgCPU < cpuLowThreshold && timeSinceStateChange > minStateTime { return .waitingForInput }
      return .thinking
    }
  }

  private func emit(_ state: SessionState, cpu: Double, memory: UInt64) {
    currentState = state
    stateStartTime = Date()
    let cb = onStateChange
    let pid = claudePID
    DispatchQueue.main.async { cb?(SessionMonitorInfo(state: state, cpu: cpu, memory: memory, pid: pid)) }
  }

  private func reportStats(cpu: Double, memory: UInt64) {
    let state = currentState
    let cb = onStateChange
    let pid = claudePID
    DispatchQueue.main.async { cb?(SessionMonitorInfo(state: state, cpu: cpu, memory: memory, pid: pid)) }
  }
}



#Preview("Terminal") {
  TerminalView(session: nil)
    .frame(width: 600, height: 400)
}
