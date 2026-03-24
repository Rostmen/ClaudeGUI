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
  let session: ClaudeSession
  var runtimeState: SessionRuntimeRegistry

  /// Animation state for blinking dot
  @State private var isBlinking = false

  /// Get the runtime info - accessing this in body sets up observation
  private var runtimeInfo: SessionRuntimeInfo {
    runtimeState.info(for: session.id)
  }

  private var isActive: Bool {
    runtimeInfo.state != .inactive
  }

  /// Whether the dot should blink (waiting for user input or permission)
  private var shouldBlink: Bool {
    isActive && (runtimeInfo.hookState == .waiting || runtimeInfo.hookState == .waitingPermission)
  }

  /// Status dot color based on hook state (only if active) or CPU state
  private var statusColor: Color {
    // Only use hook state if session is active (has running process)
    if isActive, let hookState = runtimeInfo.hookState {
      switch hookState {
      case .thinking, .processing:
        return .yellow  // Working
      case .waiting:
        return .green   // Ready for input
      case .waitingPermission:
        return .red     // Waiting for permission approval
      case .started:
        return .blue    // Just started
      case .ended:
        return .gray    // Session ended
      case .unknown:
        return .green
      }
    }
    // Fallback to CPU-based state or inactive
    return isActive ? .green : .gray
  }

  /// Status text based on hook state (only if active)
  private var statusText: String? {
    // Only show hook status if session is active
    guard isActive, let hookState = runtimeInfo.hookState else { return nil }
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
      // Row 1: Status dot + Session name
      HStack(spacing: 8) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
          .opacity(shouldBlink ? (isBlinking ? 0.3 : 1.0) : 1.0)
          .animation(shouldBlink ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: isBlinking)

        Text(session.title)
          .font(.headline)
          .foregroundColor(ClaudeTheme.textPrimary)
          .lineLimit(1)

        Spacer()
      }
      .onChange(of: shouldBlink) { _, newValue in
        if newValue {
          isBlinking = true
        } else {
          isBlinking = false
        }
      }
      .onAppear {
        if shouldBlink {
          isBlinking = true
        }
      }

      // Row 2: Date + Project path
      HStack(spacing: 6) {
        Text(session.lastModified, format: .dateTime.month(.abbreviated).day().hour().minute())
          .font(.caption)
          .foregroundColor(ClaudeTheme.textSecondary)

        Text("|")
          .font(.caption)
          .foregroundColor(ClaudeTheme.textTertiary)

        Text(session.displayPath)
          .font(.caption)
          .foregroundColor(ClaudeTheme.textSecondary)
          .lineLimit(1)
          .truncationMode(.head)
      }
      .padding(.leading, 16) // Align with text after dot

      // Row 3: PID | CPU | MEM (only when active)
      if isActive, runtimeInfo.pid > 0 {
        HStack(spacing: 6) {
          Text("PID: \(String(format: "%d", runtimeInfo.pid))")
            .font(.caption2)
            .foregroundColor(ClaudeTheme.textSecondary)
            .monospacedDigit()

          if runtimeInfo.cpu > 0 {
            Text("|")
              .font(.caption2)
              .foregroundColor(ClaudeTheme.textTertiary)
            Text(String(format: "%.1f%% CPU", runtimeInfo.cpu))
              .font(.caption2)
              .foregroundColor(cpuColor(runtimeInfo.cpu))
              .monospacedDigit()
          }

          if runtimeInfo.memory > 0 {
            Text("|")
              .font(.caption2)
              .foregroundColor(ClaudeTheme.textTertiary)
            Text(formatMemory(runtimeInfo.memory))
              .font(.caption2)
              .foregroundColor(ClaudeTheme.textSecondary)
              .monospacedDigit()
          }
        }
        .padding(.leading, 16)
      }

      // Row 4: Hook status with link icon (only when active and has hook state)
      if isActive, let status = statusText {
        HStack(spacing: 4) {
          if runtimeInfo.hookState != nil {
            Image(systemName: "link")
              .font(.caption2)
              .foregroundColor(.green)
              .help("Hooks connected - receiving real-time state updates")
          }
          Text(status)
            .font(.caption2)
            .foregroundColor(statusColor)
            .lineLimit(1)
        }
        .padding(.leading, 16)
      }
    }
    .padding(.vertical, 4)
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

  /// Format tool name for display (e.g., "Bash" -> "Running Bash")
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
}
