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

/// Form for creating a scheduled task. Built around `ScheduledTaskFormModel`, which
/// validates every field and produces a `ScheduledTaskRecord` ready to insert.
struct CreateScheduledTaskView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(AppModel.self) private var appModel

  @State private var model = ScheduledTaskFormModel()
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView { form.padding(20) }
        .frame(minHeight: 420)
      Divider()
      footer
    }
    .frame(minWidth: 520, idealWidth: 560)
    .background(ClaudeTheme.surface)
  }

  // MARK: - Header / Footer

  @ViewBuilder
  private var header: some View {
    HStack {
      Text("New Scheduled Task")
        .font(.title3)
        .bold()
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  @ViewBuilder
  private var footer: some View {
    HStack {
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundColor(.red)
          .lineLimit(2)
      }
      Spacer()
      Button("Cancel") { dismiss() }
        .keyboardShortcut(.cancelAction)
      Button("Save", action: save)
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canSave)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  // MARK: - Form sections

  @ViewBuilder
  private var form: some View {
    VStack(alignment: .leading, spacing: 18) {
      nameSection
      folderSection
      frequencySection
      promptSection
      permissionsSection
    }
  }

  @ViewBuilder
  private var nameSection: some View {
    formGroup("Name") {
      TextField("e.g. Refresh PR list", text: $model.name)
        .textFieldStyle(.roundedBorder)
    }
  }

  @ViewBuilder
  private var folderSection: some View {
    formGroup("Working folder") {
      HStack {
        Text(model.workingDirectory.isEmpty ? "No folder selected" : model.workingDirectory)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundColor(model.workingDirectory.isEmpty ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Choose…") { pickFolder() }
      }

      Toggle("Create a fresh git worktree for every run", isOn: $model.useWorktree)
        .toggleStyle(.checkbox)
        .font(.caption)

      Text(model.gitStrategyDescription)
        .font(.caption2)
        .foregroundColor(.secondary)

      if model.useWorktree && model.shouldOfferGitInit {
        Toggle(
          "Initialize git in this folder on first run",
          isOn: $model.acknowledgeGitInit
        )
        .toggleStyle(.checkbox)
        .font(.caption)
      }

      if model.useWorktree {
        DisclosureGroup("Worktree location (optional)") {
          HStack {
            TextField("Default: <repo>/.claude/worktrees", text: $model.customWorktreeBase)
              .textFieldStyle(.roundedBorder)
            Button("Browse…") { pickWorktreeBase() }
          }
        }
        .font(.caption)
      }
    }
  }

  @ViewBuilder
  private var frequencySection: some View {
    formGroup("Frequency") {
      HStack(spacing: 8) {
        Text("Every")
        Stepper(value: $model.frequencyValue, in: 1...999) {
          TextField("", value: $model.frequencyValue, format: .number)
            .frame(width: 56)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
        }
        Picker("", selection: $model.frequencyUnit) {
          ForEach(ScheduledTaskFrequencyUnit.allCases) { u in
            Text(u.displayName).tag(u)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }

      if model.frequencyUnit.requiresWeekdays {
        weekdayPicker
      }

      if model.frequencyUnit.requiresTimeOfDay {
        HStack {
          Text("At").foregroundColor(.secondary)
          DatePicker("", selection: $model.timeOfDay, displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
      }
    }
  }

  @ViewBuilder
  private var weekdayPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Days").font(.caption).foregroundColor(.secondary)
      HStack(spacing: 6) {
        ForEach(ScheduledTaskWeekday.orderedForCurrentLocale(), id: \.self) { day in
          let isOn = model.weekdays.contains(day)
          Button(action: { model.toggle(weekday: day) }) {
            Text(day.narrowName)
              .font(.caption)
              .frame(width: 28, height: 28)
              .background(isOn ? ClaudeTheme.accent.opacity(0.7) : Color.clear)
              .foregroundColor(isOn ? .white : .primary)
              .clipShape(Circle())
              .overlay(Circle().strokeBorder(ClaudeTheme.accent.opacity(0.5)))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private var promptSection: some View {
    formGroup("Prompt") {
      Picker("", selection: $model.promptKind) {
        Text("Text").tag(ScheduledTaskPromptKind.text)
        Text("File").tag(ScheduledTaskPromptKind.file)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      switch model.promptKind {
      case .text:
        TextEditor(text: $model.promptText)
          .font(.body.monospaced())
          .frame(minHeight: 96)
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
      case .file:
        HStack {
          TextField("/absolute/path/to/prompt.txt", text: $model.promptFilePath)
            .textFieldStyle(.roundedBorder)
          Button("Browse…") { pickPromptFile() }
        }
        Text("File is re-read on every execution.")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
  }

  @ViewBuilder
  private var permissionsSection: some View {
    formGroup("Permissions") {
      PermissionEditorView(settings: $model.permissionSettings)
    }
  }

  @ViewBuilder
  private func formGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.headline)
      content()
    }
  }

  // MARK: - Pickers

  private func pickFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose working folder"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    if panel.runModal() == .OK, let url = panel.url {
      model.workingDirectory = url.path
      model.refreshGitStatus(using: appModel.gitService)
      // Refresh permission defaults for this project path on first selection.
      if model.permissionSettings == .empty {
        model.permissionSettings = ClaudeSettingsService.mergeForNewSession(projectPath: url.path)
      }
    }
  }

  private func pickWorktreeBase() {
    let panel = NSOpenPanel()
    panel.title = "Choose worktree base directory"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    if panel.runModal() == .OK, let url = panel.url {
      model.customWorktreeBase = url.path
    }
  }

  private func pickPromptFile() {
    let panel = NSOpenPanel()
    panel.title = "Choose prompt file"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      model.promptFilePath = url.path
    }
  }

  // MARK: - Save

  private func save() {
    do {
      let record = try model.makeRecord()
      try appModel.scheduledTaskStore.insert(record)
      dismiss()
    } catch {
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }
}

// MARK: - Form model

/// Holds the form's editable state and produces a validated `ScheduledTaskRecord`.
@Observable
final class ScheduledTaskFormModel {
  var name: String = ""
  var workingDirectory: String = ""
  var customWorktreeBase: String = ""

  /// Default OFF: most tasks run in-place. Users opt in to per-run worktrees when
  /// they want branch isolation.
  var useWorktree: Bool = false

  /// Set by `refreshGitStatus` after the user picks a folder.
  private(set) var folderIsGitRepo: Bool = false
  /// User must explicitly opt in to git init for non-git folders (only when useWorktree).
  var acknowledgeGitInit: Bool = false

  var frequencyUnit: ScheduledTaskFrequencyUnit = .hour
  var frequencyValue: Int = 1
  var timeOfDay: Date = ScheduledTaskFormModel.defaultTimeOfDay()
  var weekdays: Set<ScheduledTaskWeekday> = []

  var promptKind: ScheduledTaskPromptKind = .text
  var promptText: String = ""
  var promptFilePath: String = ""

  var permissionSettings: ClaudePermissionSettings = .empty

  enum FormError: LocalizedError {
    case missingName
    case missingFolder
    case folderUnsupported
    case missingPromptText
    case missingPromptFile
    case frequencyInvalid(reason: String)

    var errorDescription: String? {
      switch self {
      case .missingName: return "Name is required."
      case .missingFolder: return "Pick a working folder."
      case .folderUnsupported:
        return "Folder is not a git repo. Enable the git-init checkbox to allow Tenvy to initialize one on first run."
      case .missingPromptText: return "Enter a prompt."
      case .missingPromptFile: return "Pick a prompt file."
      case .frequencyInvalid(let reason): return reason
      }
    }
  }

  // MARK: - Derived

  var shouldOfferGitInit: Bool {
    !workingDirectory.isEmpty && !folderIsGitRepo
  }

  var gitStrategyDescription: String {
    if workingDirectory.isEmpty { return "" }
    if !useWorktree {
      return "Runs directly in the folder. No git required."
    }
    if folderIsGitRepo {
      return "Each run creates a fresh worktree off the current branch."
    }
    return "Folder is not a git repository. Tenvy will run `git init` on first execution."
  }

  var canSave: Bool {
    validate() == nil
  }

  func toggle(weekday: ScheduledTaskWeekday) {
    if weekdays.contains(weekday) { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
  }

  func refreshGitStatus(using gitService: GitService) {
    folderIsGitRepo = gitService.findRepoRoot(from: workingDirectory) != nil
    acknowledgeGitInit = false
  }

  // MARK: - Validation

  func validate() -> FormError? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .missingName }
    guard !workingDirectory.isEmpty else { return .missingFolder }
    if useWorktree && !folderIsGitRepo && !acknowledgeGitInit { return .folderUnsupported }

    switch promptKind {
    case .text:
      let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedPrompt.isEmpty { return .missingPromptText }
    case .file:
      if promptFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .missingPromptFile
      }
    }

    if let reason = makeFrequency().validationError() {
      return .frequencyInvalid(reason: reason)
    }
    return nil
  }

  // MARK: - Build record

  func makeRecord(now: Date = Date()) throws -> ScheduledTaskRecord {
    if let err = validate() { throw err }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let frequency = makeFrequency()
    let next = frequency.nextRunAt(createdAt: now, from: now)

    return ScheduledTaskRecord(
      id: UUID().uuidString,
      name: trimmed,
      workingDirectory: workingDirectory,
      customWorktreeBase: useWorktree && !customWorktreeBase.isEmpty ? customWorktreeBase : nil,
      pendingGitInit: useWorktree && !folderIsGitRepo,
      useWorktree: useWorktree,
      frequencyUnit: frequencyUnit.rawValue,
      frequencyValue: frequencyValue,
      timeOfDayHour: frequencyUnit.requiresTimeOfDay ? hourOfTimeOfDay : nil,
      timeOfDayMinute: frequencyUnit.requiresTimeOfDay ? minuteOfTimeOfDay : nil,
      weekdays: frequencyUnit.requiresWeekdays ? ScheduledTaskWeekday.encode(weekdays) : nil,
      promptKind: promptKind.rawValue,
      promptText: promptKind == .text ? promptText : nil,
      promptFilePath: promptKind == .file ? promptFilePath : nil,
      permissionSettings: ScheduledTaskRecord.encode(permissionSettings),
      enabled: true,
      createdAt: now,
      lastRunAt: nil,
      lastRunStatus: nil,
      lastRunMessage: nil,
      lastRunSessionId: nil,
      nextRunAt: next
    )
  }

  private func makeFrequency() -> ScheduledTaskFrequency {
    ScheduledTaskFrequency(
      unit: frequencyUnit,
      value: frequencyValue,
      timeOfDay: frequencyUnit.requiresTimeOfDay ? currentTimeOfDay : nil,
      weekdays: frequencyUnit.requiresWeekdays ? weekdays : nil
    )
  }

  private var currentTimeOfDay: ScheduledTaskTimeOfDay {
    ScheduledTaskTimeOfDay(hour: hourOfTimeOfDay, minute: minuteOfTimeOfDay)
  }

  private var hourOfTimeOfDay: Int {
    Calendar.current.component(.hour, from: timeOfDay)
  }

  private var minuteOfTimeOfDay: Int {
    Calendar.current.component(.minute, from: timeOfDay)
  }

  // MARK: - Defaults

  private static func defaultTimeOfDay() -> Date {
    var comps = DateComponents()
    comps.hour = 9
    comps.minute = 0
    return Calendar.current.date(from: comps) ?? Date()
  }
}
