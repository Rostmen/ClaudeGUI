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

struct TerminalView: View {
  let session: ClaudeSession?
  let isSelected: Bool
  let onStateChange: ((SessionMonitorInfo) -> Void)?
  let onShellStart: ((pid_t) -> Void)?

  init(
    session: ClaudeSession?,
    isSelected: Bool = false,
    onStateChange: ((SessionMonitorInfo) -> Void)? = nil,
    onShellStart: ((pid_t) -> Void)? = nil
  ) {
    self.session = session
    self.isSelected = isSelected
    self.onStateChange = onStateChange
    self.onShellStart = onShellStart
  }

  var body: some View {
    TerminalContentView(session: session, isSelected: isSelected, onStateChange: onStateChange, onShellStart: onShellStart)
  }
}

struct TerminalContentView: NSViewRepresentable {
  let session: ClaudeSession?
  let isSelected: Bool
  let onStateChange: ((SessionMonitorInfo) -> Void)?
  let onShellStart: ((pid_t) -> Void)?

  func makeNSView(context: Context) -> DraggableTerminalView {
    let terminalView = DraggableTerminalView(frame: .zero)
    terminalView.onStateChange = onStateChange
    terminalView.onShellStart = onShellStart
    terminalView.sessionId = session?.id
    terminalView.isNewSession = session?.isNewSession ?? false

    terminalView.installColors(TerminalColors.darkPalette)
    terminalView.nativeBackgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: kWindowOpacity)
    terminalView.nativeForegroundColor = NSColor(calibratedWhite: 1, alpha: 1)

    terminalView.wantsLayer = true
    terminalView.layer?.backgroundColor = NSColor.clear.cgColor

    // Configure scroll view for overlay style scrollers (thin, translucent)
    terminalView.configureScrollerStyle()

    terminalView.registerForDraggedTypes([.fileURL])

    context.coordinator.terminalView = terminalView
    context.coordinator.startProcess(in: terminalView, session: session)

    if isSelected {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
    context.coordinator.onStateChange = onStateChange

    if context.coordinator.currentSessionId != session?.id {
      context.coordinator.currentSessionId = session?.id
      context.coordinator.startProcess(in: nsView, session: session)
    }

    if isSelected {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        if nsView.window?.firstResponder != nsView {
          nsView.window?.makeFirstResponder(nsView)
        }
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(currentSessionId: session?.id, onStateChange: onStateChange)
  }

  class Coordinator {
    var currentSessionId: String?
    var terminalView: DraggableTerminalView?
    var onStateChange: ((SessionMonitorInfo) -> Void)?

    init(currentSessionId: String?, onStateChange: ((SessionMonitorInfo) -> Void)?) {
      self.currentSessionId = currentSessionId
      self.onStateChange = onStateChange
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

      // Set working directory
      let workingDirectory = session?.workingDirectory ?? NSHomeDirectory()
      terminalView.workingDirectory = workingDirectory
      FileManager.default.changeCurrentDirectoryPath(workingDirectory)

      // Launch through a login+interactive shell so ~/.zprofile and ~/.zshrc
      // are sourced. `exec` replaces the shell with claude (same PID).
      let launch = TerminalEnvironment.shellArgs(executable: claudePath, args: args)
      terminalView.startProcess(
        executable: launch.executable,
        args: launch.args,
        environment: env,
        execName: "claude"
      )
    }
  }
}

class DraggableTerminalView: LocalProcessTerminalView {
  var onStateChange: ((SessionMonitorInfo) -> Void)?
  var onShellStart: ((pid_t) -> Void)?
  var sessionId: String?
  var isNewSession: Bool = false  // New sessions don't have their ID in process args
  var workingDirectory: String?
  private var currentState: SessionState = .inactive
  private var hasStarted = false
  private var stateMonitor: SessionStateMonitor?
  private var registeredPID: pid_t = 0

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

    // Track session for hook detection and mark as activated
    // Events before activation time will be ignored (prevents stale state)
    if let sessionId = sessionId {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        AppState.shared.markSessionActivated(sessionId)
        AppState.shared.trackSessionForHooks(sessionId)
        // Register terminal for remote input (notification actions)
        TerminalRegistry.shared.register(self, for: sessionId)
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

  // Override dataReceived from LocalProcessDelegate to intercept terminal data
  override func dataReceived(slice: ArraySlice<UInt8>) {
    // Call super to ensure data is processed by the terminal
    super.dataReceived(slice: slice)

    // Start monitoring once we receive data (process has started)
    if !hasStarted {
      hasStarted = true
      // Small delay to ensure process is fully started
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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
  }

  /// Terminate the running process and its children
  func terminateProcess() {
    if registeredPID > 0 {
      ProcessManager.shared.terminateProcess(pid: registeredPID)
      registeredPID = 0
    }
  }

  /// Restart the session - terminates current process and starts a new one
  func restartSession() {
    // Stop monitoring
    stopStateMonitoring()

    // Terminate current process
    if registeredPID > 0 {
      ProcessManager.shared.terminateProcess(pid: registeredPID)
      registeredPID = 0
    }

    // Reset state
    hasStarted = false

    // Small delay to ensure process is terminated, then restart
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }

      let claudePath = ClaudePathResolver.findClaudePath()

      // Build arguments - resume existing session
      var args: [String] = []
      if let sessionId = self.sessionId {
        args = ["--resume", sessionId]
      }

      // Build environment with terminal settings
      let env = TerminalEnvironment.build()

      // Set working directory
      if let workingDir = self.workingDirectory {
        FileManager.default.changeCurrentDirectoryPath(workingDir)
      }

      let launch = TerminalEnvironment.shellArgs(executable: claudePath, args: args)
      self.startProcess(
        executable: launch.executable,
        args: launch.args,
        environment: env,
        execName: "claude"
      )
    }
  }

  deinit {
    // Unregister from terminal registry
    if let sessionId = sessionId {
      Task { @MainActor in
        TerminalRegistry.shared.unregister(sessionId: sessionId)
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

class SessionStateMonitor {
  let shellPID: pid_t
  let sessionId: String?
  var onStateChange: ((SessionMonitorInfo) -> Void)?

  private var pollTimer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "SessionStateMonitor", qos: .utility)
  private var currentState: SessionState = .inactive
  private var cpuHistory: [Double] = []
  private var stateStartTime: Date = Date()
  private var processStartTime: Date = Date()
  private var lastReportedCPU: Double = 0
  private var lastReportedMemory: UInt64 = 0
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
    self.processStartTime = Date()
  }

  func start() {
    // Start polling for CPU usage
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
    timer.setEventHandler { [weak self] in self?.checkCPU() }
    timer.resume()
    pollTimer = timer

    // Initial state
    emit(.waitingForInput, cpu: 0, memory: 0)
  }

  func stop() {
    pollTimer?.cancel()
    pollTimer = nil
  }

  private func checkCPU() {
    let pid = findClaudeProcess()
    claudePID = pid

    guard pid > 0, let stats = getProcessStats(pid: pid) else {
      emit(.inactive, cpu: 0, memory: 0)
      return
    }

    let cpu = stats.cpu
    let memory = stats.memory
    lastReportedMemory = memory

    // Update CPU history for rolling average
    cpuHistory.append(cpu)
    if cpuHistory.count > historySize {
      cpuHistory.removeFirst()
    }

    let avgCPU = cpuHistory.reduce(0, +) / Double(cpuHistory.count)
    let timeSinceStart = Date().timeIntervalSince(processStartTime)
    let timeSinceStateChange = Date().timeIntervalSince(stateStartTime)

    // State machine based on ClaudeCodeMonitor logic
    let newState = deriveState(avgCPU: avgCPU, timeSinceStart: timeSinceStart, timeSinceStateChange: timeSinceStateChange)

    // Always report CPU/memory, emit state change if needed
    if newState != currentState {
      emit(newState, cpu: avgCPU, memory: memory)
    } else {
      // Report CPU/memory update even without state change
      reportStats(cpu: avgCPU, memory: memory)
    }
  }

  /// Find Claude process that is a descendant of our shell
  private func findClaudeProcess() -> pid_t {
    ProcessTreeAnalyzer.findClaudeProcess(shellPID: shellPID, sessionId: sessionId)
  }

  private func deriveState(avgCPU: Double, timeSinceStart: TimeInterval, timeSinceStateChange: TimeInterval) -> SessionState {
    switch currentState {
    case .inactive, .waitingForInput:
      // Transition to thinking if CPU is high
      if avgCPU > cpuHighThreshold && timeSinceStart > minRunningTime {
        return .thinking
      }
      // Stay in waiting state if process is running
      return .waitingForInput

    case .thinking:
      // Transition to waiting if CPU drops low for a while
      if avgCPU < cpuLowThreshold && timeSinceStateChange > minStateTime {
        return .waitingForInput
      }
      // Stay thinking if CPU is still high
      return .thinking
    }
  }

  private func emit(_ state: SessionState, cpu: Double, memory: UInt64) {
    currentState = state
    stateStartTime = Date()
    lastReportedCPU = cpu
    lastReportedMemory = memory
    let cb = onStateChange
    let pid = claudePID
    DispatchQueue.main.async { cb?(SessionMonitorInfo(state: state, cpu: cpu, memory: memory, pid: pid)) }
  }

  private func reportStats(cpu: Double, memory: UInt64) {
    lastReportedCPU = cpu
    lastReportedMemory = memory
    let state = currentState
    let cb = onStateChange
    let pid = claudePID
    DispatchQueue.main.async { cb?(SessionMonitorInfo(state: state, cpu: cpu, memory: memory, pid: pid)) }
  }

  /// Get CPU and memory usage for a specific process using ps command
  /// Returns (cpu percentage, memory in bytes) or nil if process not found
  private func getProcessStats(pid: pid_t) -> (cpu: Double, memory: UInt64)? {
    let task = Process()
    task.launchPath = "/bin/bash"
    // %cpu = CPU percentage, rss = resident set size in KB, pid = process ID
    task.arguments = ["-c", "ps -A -o %cpu,rss,pid"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    guard let output = String(data: data, encoding: .utf8) else { return nil }

    let lines = output.components(separatedBy: "\n")
    for line in lines {
      let components = line.trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
      // Expecting: %cpu, rss (KB), pid
      guard components.count >= 3,
         let cpuString = components[safe: 0],
         let rssString = components[safe: 1],
         let pidString = components[safe: 2],
         let linePid = Int32(pidString),
         linePid == pid,
         let cpu = Double(cpuString),
         let rssKB = UInt64(rssString) else {
        continue
      }
      // Convert KB to bytes
      let memoryBytes = rssKB * 1024
      return (cpu, memoryBytes)
    }
    return nil
  }
}

// MARK: - Safe Array Access
private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

enum TerminalColors {
  /// SwiftTerm's default dark palette
  static let darkPalette: [SwiftTerm.Color] = [
    SwiftTerm.Color(red: 0, green: 0, blue: 0),                           // 0  black
    SwiftTerm.Color(red: 194 * 257, green: 54 * 257, blue: 33 * 257),     // 1  red
    SwiftTerm.Color(red: 37 * 257, green: 188 * 257, blue: 36 * 257),     // 2  green
    SwiftTerm.Color(red: 173 * 257, green: 173 * 257, blue: 39 * 257),    // 3  yellow
    SwiftTerm.Color(red: 73 * 257, green: 46 * 257, blue: 225 * 257),     // 4  blue
    SwiftTerm.Color(red: 211 * 257, green: 56 * 257, blue: 211 * 257),    // 5  magenta
    SwiftTerm.Color(red: 51 * 257, green: 187 * 257, blue: 200 * 257),    // 6  cyan
    SwiftTerm.Color(red: 203 * 257, green: 204 * 257, blue: 205 * 257),   // 7  white
    SwiftTerm.Color(red: 129 * 257, green: 131 * 257, blue: 131 * 257),   // 8  bright black
    SwiftTerm.Color(red: 252 * 257, green: 57 * 257, blue: 31 * 257),     // 9  bright red
    SwiftTerm.Color(red: 49 * 257, green: 231 * 257, blue: 34 * 257),     // 10 bright green
    SwiftTerm.Color(red: 234 * 257, green: 236 * 257, blue: 35 * 257),    // 11 bright yellow
    SwiftTerm.Color(red: 88 * 257, green: 51 * 257, blue: 255 * 257),     // 12 bright blue
    SwiftTerm.Color(red: 249 * 257, green: 53 * 257, blue: 248 * 257),    // 13 bright magenta
    SwiftTerm.Color(red: 20 * 257, green: 240 * 257, blue: 240 * 257),    // 14 bright cyan
    SwiftTerm.Color(red: 233 * 257, green: 235 * 257, blue: 235 * 257),   // 15 bright white
  ]
}

#Preview("Terminal") {
  TerminalView(session: nil)
    .frame(width: 600, height: 400)
}
