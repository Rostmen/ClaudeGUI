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
import GRDBQuery

/// Push view shown when the user taps a scheduled task row in the sidebar.
///
/// Layout (per design §3.4): compact header (back, task name, status icon, enable toggle,
/// delete button), an expandable "Show details" disclosure with the full config and prompt
/// preview, and the list of sessions spawned by this task. Disabling a task with a running
/// session opens a confirmation sheet (stop / let-finish / cancel).
struct ScheduledTaskDetailView: View {
  let taskId: String
  var onBack: () -> Void
  var onMissing: () -> Void

  @Environment(AppModel.self) private var appModel
  @Query<ScheduledTaskByIdRequest> private var task: ScheduledTaskRecord?
  @Query<SessionsByScheduledTaskRequest> private var sessions: [SessionRecord]
  @Binding var selectedSession: ClaudeSession?

  @State private var detailsExpanded = false
  @State private var showPromptSheet = false
  @State private var showDisableConfirmation = false
  @State private var showDeleteFlow = false
  @State private var errorMessage: String?

  init(
    taskId: String,
    selectedSession: Binding<ClaudeSession?>,
    onBack: @escaping () -> Void,
    onMissing: @escaping () -> Void = {}
  ) {
    self.taskId = taskId
    self.onBack = onBack
    self.onMissing = onMissing
    self._selectedSession = selectedSession
    self._task = Query(constant: ScheduledTaskByIdRequest(id: taskId))
    self._sessions = Query(constant: SessionsByScheduledTaskRequest(scheduledTaskId: taskId))
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      detailsDisclosure
      Divider()
      sessionList
    }
    .background(ClaudeTheme.surface.opacity(0.02))
    .sheet(isPresented: $showPromptSheet) {
      if let task { PromptPreviewSheet(task: task) }
    }
    .sheet(isPresented: $showDisableConfirmation) {
      DisableRunningTaskConfirmationView(
        taskName: task?.name ?? "",
        onStopAndDisable: { stopAndDisable() },
        onLetFinish: { disableLetFinish() },
        onCancel: { showDisableConfirmation = false }
      )
    }
    .sheet(isPresented: $showDeleteFlow) {
      if let task {
        DeleteScheduledTaskConfirmationView(
          task: task,
          sessions: sessions,
          onCompleted: {
            showDeleteFlow = false
            onMissing()
          },
          onCancel: { showDeleteFlow = false }
        )
      }
    }
    .alert("Couldn't update task", isPresented: .constant(errorMessage != nil)) {
      Button("OK") { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
    .onChange(of: task?.id) { _, newId in
      if newId == nil { onMissing() }
    }
  }

  // MARK: - Header

  @ViewBuilder
  private var header: some View {
    HStack(spacing: 8) {
      Button(action: onBack) {
        Image(systemName: "chevron.left").imageScale(.medium)
      }
      .buttonStyle(.borderless)
      .help("Back to all sessions")

      VStack(alignment: .leading, spacing: 2) {
        Text(task?.name ?? "Scheduled task").font(.headline).lineLimit(1)
        Text(task?.resolvedFrequency?.displayString ?? "")
          .font(.caption)
          .foregroundColor(ClaudeTheme.textSecondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Toggle("", isOn: Binding(
        get: { task?.enabled ?? false },
        set: { setEnabled($0) }
      ))
      .toggleStyle(.switch)
      .labelsHidden()
      .help(task?.enabled == true ? "Disable scheduled task" : "Enable scheduled task")

      Button(action: { showDeleteFlow = true }) {
        Image(systemName: "trash")
          .imageScale(.medium)
          .foregroundColor(.red)
      }
      .buttonStyle(.borderless)
      .help("Delete scheduled task")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  // MARK: - Details disclosure

  @ViewBuilder
  private var detailsDisclosure: some View {
    DisclosureGroup(isExpanded: $detailsExpanded) {
      VStack(alignment: .leading, spacing: 6) {
        if let task {
          detailRow("Folder", value: task.workingDirectory)
          if let worktreeBase = task.customWorktreeBase, !worktreeBase.isEmpty {
            detailRow("Worktree base", value: worktreeBase)
          }
          detailRow("Permissions", value: permissionsSummary(task.decodedPermissionSettings))
          detailRow("Prompt", value: promptPreview(task: task))
          if let last = task.lastRunAt {
            detailRow("Last run", value: ScheduledTaskCountdownFormatter.relative(from: Date(), to: last)
                      .replacingOccurrences(of: "in ", with: "")
                      + " ago — \(task.lastRunStatus ?? "")")
          }
          Button("Show full prompt") { showPromptSheet = true }
            .font(.caption)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
    } label: {
      Text("Details")
        .font(.caption)
        .foregroundColor(ClaudeTheme.textSecondary)
    }
    .padding(.horizontal, 12)
  }

  @ViewBuilder
  private func detailRow(_ label: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label + ":")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(width: 90, alignment: .trailing)
      Text(value)
        .font(.caption)
        .foregroundColor(ClaudeTheme.textPrimary)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Sessions sub-list

  @ViewBuilder
  private var sessionList: some View {
    if sessions.isEmpty {
      VStack(spacing: 6) {
        Spacer().frame(height: 24)
        Image(systemName: "tray")
          .imageScale(.large)
          .foregroundColor(ClaudeTheme.textSecondary)
        Text("No runs yet").font(.caption).foregroundColor(ClaudeTheme.textSecondary)
        Spacer()
      }
      .frame(maxWidth: .infinity)
    } else {
      List {
        Section {
          ForEach(sessions) { record in
            let session = buildSession(from: record)
            SessionRowView(
              sessionModel: ClaudeSessionModel(
                session: session,
                runtime: appModel.runtimeRegistry.info(for: session.id)
              ),
              isActive: record.isActive
            )
            .contentShape(Rectangle())
            .onTapGesture { selectedSession = session }
          }
        } header: {
          Text("Sessions (\(sessions.count))")
            .font(.caption)
            .foregroundColor(ClaudeTheme.textSecondary)
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
  }

  // MARK: - Helpers

  private func buildSession(from record: SessionRecord) -> ClaudeSession {
    ClaudeSession(
      id: record.claudeSessionId ?? record.tenvySessionId,
      title: record.title,
      projectPath: record.projectPath,
      workingDirectory: record.workingDirectory,
      lastModified: record.lastModifiedAt,
      filePath: record.sessionFilePath.flatMap(URL.init(fileURLWithPath:)),
      isNewSession: false,
      tenvySessionId: record.tenvySessionId
    )
  }

  private func promptPreview(task: ScheduledTaskRecord) -> String {
    if task.resolvedPromptKind == .file {
      return "File: \(task.promptFilePath ?? "—")"
    }
    let text = task.promptText ?? ""
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "—" }
    if trimmed.count <= 140 { return trimmed }
    return String(trimmed.prefix(140)) + "…"
  }

  private func permissionsSummary(_ settings: ClaudePermissionSettings) -> String {
    let mode = settings.permissionMode.displayName
    let allow = settings.permissions.allow.count
    let deny = settings.permissions.deny.count
    let ask = settings.permissions.ask.count
    return "\(mode) — \(allow) allow, \(deny) deny, \(ask) ask"
  }

  // MARK: - Enable / disable

  private func setEnabled(_ enabled: Bool) {
    guard let task else { return }
    if !enabled && hasRunningSession(task: task) {
      showDisableConfirmation = true
      return
    }
    applyEnabled(enabled)
  }

  private func applyEnabled(_ enabled: Bool) {
    guard let task else { return }
    do {
      let nextRunAt: Date? = enabled
        ? task.resolvedFrequency?.nextRunAt(createdAt: task.createdAt, from: Date())
        : nil
      try appModel.scheduledTaskStore.setEnabled(
        id: task.id, enabled: enabled, nextRunAt: nextRunAt
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func hasRunningSession(task: ScheduledTaskRecord) -> Bool {
    guard let priorTenvyId = task.lastRunSessionId else { return false }
    return appModel.activatedSessions.values.contains { $0.tenvySessionId == priorTenvyId }
  }

  private func stopAndDisable() {
    showDisableConfirmation = false
    if let task, let priorTenvyId = task.lastRunSessionId {
      // Find the active session and close its window.
      if let session = appModel.activatedSessions.values.first(where: { $0.tenvySessionId == priorTenvyId }) {
        if let window = appModel.windowRegistry.window(for: session.id) {
          window.close()
        }
        appModel.deactivateSession(session.id)
      }
    }
    applyEnabled(false)
  }

  private func disableLetFinish() {
    showDisableConfirmation = false
    applyEnabled(false)
  }
}

// MARK: - Disable-running confirmation sheet

private struct DisableRunningTaskConfirmationView: View {
  let taskName: String
  var onStopAndDisable: () -> Void
  var onLetFinish: () -> Void
  var onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Disable \"\(taskName)\"?")
        .font(.headline)
      Text("This task currently has a running session. What should happen to it?")
        .font(.body)
      HStack {
        Button("Cancel", action: onCancel)
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Disable, let current run finish", action: onLetFinish)
        Button("Stop & disable", role: .destructive, action: onStopAndDisable)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(minWidth: 420)
  }
}

// MARK: - Prompt preview sheet

private struct PromptPreviewSheet: View {
  let task: ScheduledTaskRecord
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Prompt").font(.headline)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
      ScrollView {
        if task.resolvedPromptKind == .file {
          Text("File: \(task.promptFilePath ?? "—")")
            .font(.body.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
          Text("Re-read on every execution.")
            .font(.caption2)
            .foregroundColor(.secondary)
        } else {
          Text(task.promptText ?? "")
            .font(.body.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(20)
    .frame(minWidth: 480, minHeight: 320)
  }
}
