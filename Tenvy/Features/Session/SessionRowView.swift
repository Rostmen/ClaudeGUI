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

struct SessionRowView: View {
  let sessionModel: ClaudeSessionModel
  /// Whether this session is in the activated set — the single source of truth for "active".
  /// Passed by the parent list which owns `activeSessionIds`.
  var isActive: Bool = false
  /// Override title (e.g. for plain terminals whose Ghostty surface title changes at runtime).
  var titleOverride: String?

  /// Animation state for blinking dot
  @State private var isBlinking = false

  private var session: ClaudeSession { sessionModel.session }

  /// Get the runtime info - accessing this in body sets up observation
  private var runtimeInfo: SessionRuntimeInfo { sessionModel.runtime }

  /// Resolved hook state — in-memory runtimeInfo is the source of truth.
  /// DB record is no longer updated on every hook event (to avoid @Query storm).
  private var effectiveHookState: HookState? {
    runtimeInfo.hookState
  }

  /// Whether the dot should blink (waiting for user input or permission)
  private var shouldBlink: Bool {
    isActive && (effectiveHookState == .waiting || effectiveHookState == .waitingPermission)
  }

  /// Status dot color based on hook state (only if active) or CPU state
  private var statusColor: Color {
    if isActive, let hookState = effectiveHookState {
      return hookState.statusColor
    }
    return isActive ? .green : .gray
  }

  /// Status text based on hook state (only if active)
  private var statusText: String? {
    // Only show hook status if session is active
    guard isActive, let hookState = effectiveHookState else { return nil }
    switch hookState {
      case .thinking:
        if let tool = runtimeInfo.currentTool {
          return formatToolName(tool)
        }
        return "Thinking..."
      case .processing:
        return "Processing..."
      case .waiting:
        return "Waiting"
      case .waitingPermission:
        return "Needs Permission"
      case .started:
        return "Started"
      case .ended, .unknown:
        return nil
    }
  }
  
  var body: some View {
    
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        statusUpdateDot
        sessionNameRow
        Spacer()
      }
      .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 0) {
        // Indent to align with the title (dot width + spacing)
        Spacer().frame(width: 16)
        VStack(alignment: .leading, spacing: 4) {
          dateRow
          destinationInfoRow
          processInfoRow
          hookUpdatesRow
        }
      }
    }
    .onChange(of: shouldBlink) { _, newValue in
      isBlinking = newValue
    }
    .onAppear {
      if shouldBlink {
        isBlinking = true
      }
    }
    
  }
  
  @ViewBuilder var statusUpdateDot: some View {
    Circle()
      .fill(statusColor)
      .frame(width: 8, height: 8)
      .opacity(shouldBlink ? (isBlinking ? 0.3 : 1.0) : 1.0)
      .animation(shouldBlink ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: isBlinking)
  }
  
  @ViewBuilder var sessionNameRow: some View {
    Text(titleOverride ?? session.title)
      .font(.headline)
      .foregroundColor(ClaudeTheme.textPrimary)
      .lineLimit(1)
  }
  
  @ViewBuilder var dateRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Image(systemName: "calendar")

      Text(session.lastModified, format: .dateTime.month(.abbreviated).day().hour().minute())
    }
    .font(.caption)
    .foregroundColor(ClaudeTheme.textSecondary)
  }
  
  @ViewBuilder var destinationInfoRow: some View {
    HStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Image(systemName: "folder")
        Text(session.displayPath)
      }
      .font(.caption)
      .foregroundColor(ClaudeTheme.textSecondary)
      .lineLimit(1)
      .truncationMode(.tail)
      
      if let branch = runtimeInfo.gitBranch {
        Divider()
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Image(systemName: "arrow.triangle.branch")
          Text(branch)
        }
        .font(.caption)
        .foregroundColor(.orange)
        .lineLimit(1)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
  
  // PID | CPU | MEM (only when active)
  @ViewBuilder var processInfoRow: some View {
    if isActive, runtimeInfo.pid > 0 {
      HStack(spacing: 6) {
        Text("PID: \(String(format: "%d", runtimeInfo.pid))")
          .font(.caption2)
          .foregroundColor(ClaudeTheme.textSecondary)
          .monospacedDigit()
        
        if runtimeInfo.cpu > 0 {
          Divider()
          Text(String(format: "%.1f%% CPU", runtimeInfo.cpu))
            .font(.caption2)
            .foregroundColor(cpuColor(runtimeInfo.cpu))
            .monospacedDigit()
        }
        
        if runtimeInfo.memory > 0 {
          Divider()
          Text(formatMemory(runtimeInfo.memory))
            .font(.caption2)
            .foregroundColor(ClaudeTheme.textSecondary)
            .monospacedDigit()
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }
  
  // Row 4: Hook status with link icon (only when active and has hook state)
  @ViewBuilder var hookUpdatesRow: some View {
    if isActive, let status = statusText {
      Text(status)
        .font(.caption2)
        .foregroundColor(statusColor)
        .lineLimit(1)
    }
  }
}

private func cpuColor(_ cpu: Double) -> Color {
  if cpu > 25 {
    return .yellow  // High CPU - thinking
  } else if cpu > 3 {
    return .orange  // Medium CPU
  } else {
    return .green   // Low CPU - idle
  }
}

/// Format memory in human-readable form (MB or GB)
private func formatMemory(_ bytes: UInt64) -> String {
  let mb = Double(bytes) / 1024 / 1024
  if mb >= 1024 {
    return String(format: "%.1f GB", mb / 1024)
  } else {
    return String(format: "%.0f MB", mb)
  }
}

/// Format tool name for display (e.g., "Bash" → "Running Bash")
private func formatToolName(_ tool: String) -> String {
  switch tool {
  case "Bash":
    return "Running command..."
  case "Read":
    return "Reading file..."
  case "Write":
    return "Writing file..."
  case "Edit":
    return "Editing file..."
  case "Glob":
    return "Searching files..."
  case "Grep":
    return "Searching content..."
  case "Task":
    return "Running task..."
  default:
    if tool.hasPrefix("mcp__") {
      return "Using MCP tool..."
    }
    return "Using \(tool)..."
  }
}


// MARK: - Previews

#if DEBUG

#Preview("All States") {
  VStack(alignment: .leading, spacing: 12) {
    SessionRowView(sessionModel: .previewInactive)
    Divider()
    SessionRowView(sessionModel: .previewInactiveWithBranch)
    Divider()
    SessionRowView(sessionModel: .previewThinking)
    Divider()
    SessionRowView(sessionModel: .previewRunningBash)
    Divider()
    SessionRowView(sessionModel: .previewWaiting)
    Divider()
    SessionRowView(sessionModel: .previewWaitingPermission)
    Divider()
    SessionRowView(sessionModel: .previewProcessing)
    Divider()
    SessionRowView(sessionModel: .previewStarted)
    Divider()
    SessionRowView(sessionModel: .previewNoGit)
  }
  .frame(width: 280)
  .padding()
}

#endif
