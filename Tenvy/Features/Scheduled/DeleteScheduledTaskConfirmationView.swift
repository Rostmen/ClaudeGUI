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

enum DeleteScheduledFlowPhase {
  case confirm
  case cleaning
  case done
  case partialFailure
}

/// State machine + cleanup work for the delete dialog. Lives as an `@Observable` so the
/// async cleanup task can mutate it without fighting SwiftUI's value-type / `@State` rules.
@MainActor
@Observable
final class DeleteScheduledFlowModel {
  var phase: DeleteScheduledFlowPhase = .confirm
  var deleteSpawnedSessions: Bool = true
  var deleteWorktrees: Bool = true
  var currentStep: String = ""
  var stepProgress: Double = 0
  var failedItems: [String] = []

  func startCleanup(
    appModel: AppModel,
    task: ScheduledTaskRecord,
    sessions: [SessionRecord],
    onCompleted: @escaping () -> Void
  ) async {
    phase = .cleaning

    struct Step { let label: String; let work: () async -> String? }
    var steps: [Step] = []

    if deleteSpawnedSessions {
      for record in sessions {
        let tenvyId = record.tenvySessionId
        let title = record.title
        steps.append(Step(label: "Removing session: \(title)", work: { [appModel] in
          // Resolve current state at execution time — `record.isActive` is a snapshot
          // from when the dialog opened and may be stale.
          if let session = appModel.activatedSessions.values.first(where: { $0.tenvySessionId == tenvyId }) {
            // Terminate the claude process and deactivate BEFORE closing the window
            // so `WindowDelegate.windowShouldClose` doesn't show the confirmation
            // alert. Also handles split-pane sessions (closes the pane only, not
            // the whole window). Same pattern as `ScheduledTaskExecutor.closePriorSession`.
            appModel.terminateAndCloseSession(session.id)
          }
          do {
            try appModel.sessionStore.deleteSession(tenvySessionId: tenvyId)
            return nil
          } catch {
            return "Session \(title): \(error.localizedDescription)"
          }
        }))
      }
    }

    if deleteWorktrees {
      for record in sessions {
        guard let worktreePath = record.worktreePath,
              FileManager.default.fileExists(atPath: worktreePath) else { continue }
        let projectPath = record.projectPath
        steps.append(Step(label: "Removing worktree: \(worktreePath)", work: { [appModel] in
          do {
            let git = appModel.gitService
            let repoRoot = git.findRepoRoot(from: projectPath) ?? projectPath
            try git.removeWorktree(repoPath: repoRoot, worktreePath: worktreePath)
            return nil
          } catch {
            return "Worktree \(worktreePath): \(error.localizedDescription)"
          }
        }))
      }
    }

    steps.append(Step(label: "Deleting task record", work: { [appModel, task] in
      do {
        try appModel.scheduledTaskStore.delete(id: task.id)
        return nil
      } catch {
        return "Task record: \(error.localizedDescription)"
      }
    }))

    var failures: [String] = []
    let total = max(steps.count, 1)
    for (index, step) in steps.enumerated() {
      currentStep = step.label
      stepProgress = Double(index) / Double(total)
      if let failure = await step.work() {
        failures.append(failure)
      }
    }
    stepProgress = 1.0

    if failures.isEmpty {
      phase = .done
      try? await Task.sleep(nanoseconds: 600_000_000)
      onCompleted()
    } else {
      failedItems = failures
      phase = .partialFailure
    }
  }
}

/// Stateful delete dialog for a scheduled task (§3.7 / §4.7).
struct DeleteScheduledTaskConfirmationView: View {
  let task: ScheduledTaskRecord
  let sessions: [SessionRecord]
  var onCompleted: () -> Void
  var onCancel: () -> Void

  @Environment(AppModel.self) private var appModel
  @State private var flow = DeleteScheduledFlowModel()

  private var worktreePaths: [String] {
    sessions.compactMap { record in
      record.worktreePath.flatMap { path in
        FileManager.default.fileExists(atPath: path) ? path : nil
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      Divider()
      bodyContent
      Divider()
      footer
    }
    .padding(20)
    .frame(minWidth: 480)
    .interactiveDismissDisabled(flow.phase == .cleaning)
  }

  // MARK: - Header

  @ViewBuilder
  private var header: some View {
    Text(headerText)
      .font(.title3)
      .bold()
  }

  private var headerText: String {
    switch flow.phase {
    case .confirm: return "Delete \"\(task.name)\"?"
    case .cleaning: return "Cleaning up…"
    case .done: return "Deleted"
    case .partialFailure: return "Some items couldn't be removed"
    }
  }

  // MARK: - Body

  @ViewBuilder
  private var bodyContent: some View {
    switch flow.phase {
    case .confirm:
      VStack(alignment: .leading, spacing: 10) {
        Text("This will remove the scheduled task definition.")
        if !sessions.isEmpty {
          Toggle("Also delete \(sessions.count) spawned session record(s)",
                 isOn: Binding(get: { flow.deleteSpawnedSessions },
                               set: { flow.deleteSpawnedSessions = $0 }))
        }
        if !worktreePaths.isEmpty {
          Toggle("Also delete \(worktreePaths.count) worktree director(ies)",
                 isOn: Binding(get: { flow.deleteWorktrees },
                               set: { flow.deleteWorktrees = $0 }))
          VStack(alignment: .leading, spacing: 2) {
            Text("Worktrees:").font(.caption).foregroundColor(.secondary)
            ForEach(worktreePaths.prefix(4), id: \.self) { path in
              Text(path)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            if worktreePaths.count > 4 {
              Text("…and \(worktreePaths.count - 4) more")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
          }
        }
      }

    case .cleaning:
      VStack(alignment: .leading, spacing: 8) {
        ProgressView(value: flow.stepProgress)
        Text(flow.currentStep).font(.caption).foregroundColor(.secondary).lineLimit(2)
      }

    case .done:
      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .imageScale(.large)
          .foregroundColor(.green)
        Text("Done.")
      }

    case .partialFailure:
      VStack(alignment: .leading, spacing: 6) {
        Text("Cleanup finished but some items couldn't be removed:")
        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(flow.failedItems, id: \.self) { item in
              Text("• \(item)")
                .font(.caption.monospaced())
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .frame(maxHeight: 140)
      }
    }
  }

  // MARK: - Footer

  @ViewBuilder
  private var footer: some View {
    HStack {
      Spacer()
      switch flow.phase {
      case .confirm:
        Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
        Button("Delete", role: .destructive) {
          Task { await flow.startCleanup(appModel: appModel, task: task, sessions: sessions, onCompleted: onCompleted) }
        }
        .keyboardShortcut(.defaultAction)
      case .cleaning:
        ProgressView().controlSize(.small)
      case .done:
        Button("Close", action: onCompleted).keyboardShortcut(.defaultAction)
      case .partialFailure:
        Button("Close", action: onCompleted).keyboardShortcut(.defaultAction)
      }
    }
  }
}
