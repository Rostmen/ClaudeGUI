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

/// One row in the sidebar's "Scheduled" section.
///
/// Shows a status icon, the task name, and a relative countdown (or status text for
/// non-waiting states). The countdown text re-renders once per second via a
/// `TimelineView` so it stays accurate.
struct ScheduledTaskRowView: View {
  let task: ScheduledTaskRecord

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      icon
        .frame(width: 16, height: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(task.name)
          .font(.headline)
          .foregroundColor(ClaudeTheme.textPrimary)
          .lineLimit(1)
        subtitle
          .font(.caption)
          .foregroundColor(ClaudeTheme.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
  }

  // MARK: - Status helpers

  /// Logical state shown by the icon/text.
  private enum DisplayState {
    case disabled
    case failed
    case skipped
    case running
    case waitingNext
  }

  private var displayState: DisplayState {
    if !task.enabled {
      return task.resolvedLastRunStatus == .failed ? .failed : .disabled
    }
    switch task.resolvedLastRunStatus {
    case .failed: return .failed
    case .skipped: return .skipped
    case .running: return .running
    case .completed, .none: return .waitingNext
    }
  }

  @ViewBuilder
  private var icon: some View {
    switch displayState {
    case .disabled:
      Image(systemName: "pause.circle.fill")
        .foregroundColor(.secondary)
    case .failed:
      Image(systemName: "xmark.circle.fill")
        .foregroundColor(.red)
    case .skipped:
      Image(systemName: "forward.fill")
        .foregroundColor(.orange)
    case .running:
      Image(systemName: "play.circle.fill")
        .foregroundColor(.green)
    case .waitingNext:
      Image(systemName: "clock")
        .foregroundColor(ClaudeTheme.accent)
    }
  }

  @ViewBuilder
  private var subtitle: some View {
    switch displayState {
    case .disabled:
      Text("Disabled")
    case .failed:
      if let msg = task.lastRunMessage, !msg.isEmpty {
        Text("Last run failed — \(msg)")
      } else {
        Text("Last run failed")
      }
    case .skipped:
      if let msg = task.lastRunMessage, !msg.isEmpty {
        Text("Skipped — \(msg)")
      } else {
        Text("Skipped")
      }
    case .running:
      Text("Running")
    case .waitingNext:
      // Live countdown — TimelineView refreshes at a cadence appropriate to the remaining time.
      TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
        Text(ScheduledTaskCountdownFormatter.relative(from: context.date, to: task.nextRunAt))
      }
    }
  }

  /// Adaptive refresh rate so we don't burn CPU on minute/hour-scale countdowns.
  private var refreshInterval: TimeInterval {
    let remaining = task.nextRunAt.timeIntervalSinceNow
    return ScheduledTaskCountdownFormatter.refreshInterval(remaining: remaining)
  }
}

// MARK: - Previews

#Preview("Waiting next") {
  ScheduledTaskRowView(
    task: ScheduledTaskRecord(
      id: "1", name: "Refresh PRs", workingDirectory: "/tmp",
      pendingGitInit: false, frequencyUnit: "hour", frequencyValue: 1,
      timeOfDayHour: nil, timeOfDayMinute: nil, weekdays: nil,
      promptKind: "text", promptText: nil, promptFilePath: nil,
      permissionSettings: "{}", enabled: true,
      createdAt: Date(), lastRunAt: nil, lastRunStatus: nil, lastRunMessage: nil,
      lastRunSessionId: nil, nextRunAt: Date().addingTimeInterval(180)
    )
  )
  .padding()
}

#Preview("Running") {
  ScheduledTaskRowView(
    task: ScheduledTaskRecord(
      id: "1", name: "Refresh PRs", workingDirectory: "/tmp",
      pendingGitInit: false, frequencyUnit: "hour", frequencyValue: 1,
      timeOfDayHour: nil, timeOfDayMinute: nil, weekdays: nil,
      promptKind: "text", promptText: nil, promptFilePath: nil,
      permissionSettings: "{}", enabled: true,
      createdAt: Date(), lastRunAt: Date(), lastRunStatus: "running", lastRunMessage: nil,
      lastRunSessionId: "abc", nextRunAt: Date().addingTimeInterval(3600)
    )
  )
  .padding()
}

#Preview("Skipped") {
  ScheduledTaskRowView(
    task: ScheduledTaskRecord(
      id: "1", name: "Daily summary", workingDirectory: "/tmp",
      pendingGitInit: false, frequencyUnit: "day", frequencyValue: 1,
      timeOfDayHour: 9, timeOfDayMinute: 0, weekdays: nil,
      promptKind: "text", promptText: nil, promptFilePath: nil,
      permissionSettings: "{}", enabled: true,
      createdAt: Date(), lastRunAt: Date(), lastRunStatus: "skipped",
      lastRunMessage: "Previous run still active",
      lastRunSessionId: nil, nextRunAt: Date().addingTimeInterval(86400)
    )
  )
  .padding()
}
