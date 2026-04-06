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
import CodeEditor

/// Unified dialog for creating new sessions (via "+" button) and split panes (via context menu).
/// Adapts its content based on whether git is initialized and whether this is a new session or split flow.
struct NewSessionDialogView: View {
  @Bindable var viewModel: ContentViewModel
  @State private var selectedTab: DialogTab = .git

  private enum DialogTab: String, CaseIterable {
    case git = "Git"
    case shellInitScript = "Shell Init Script"
  }

  private var isNewSessionFlow: Bool {
    viewModel.pendingSplit?.isNewSessionFlow == true
  }

  private var hasGitRepo: Bool {
    viewModel.pendingSplit?.hasGitRepo == true
  }

  private var isPlainTerminalSplit: Bool {
    viewModel.pendingSplit?.isPlainTerminalSplit == true
  }

  private var form: Binding<WorktreeSplitFormData> {
    Binding(
      get: { viewModel.worktreeSplitForm ?? WorktreeSplitFormData(
        baseBranch: "main", newBranchName: "", worktreePath: "",
        availableBranches: [], sourceSessionId: "", sourceIsNewSession: true, repoRoot: "",
        hasSubmodules: false
      )},
      set: { viewModel.worktreeSplitForm = $0 }
    )
  }

  var body: some View {
    VStack(spacing: 16) {
      if isPlainTerminalSplit {
        plainTerminalSplitHeader
        shellInitScriptContent
        plainTerminalButtonRow
      } else {
        header

        Picker("", selection: $selectedTab) {
          ForEach(DialogTab.allCases, id: \.self) { tab in
            Text(tab.rawValue).tag(tab)
          }
        }
        .pickerStyle(.segmented)

        switch selectedTab {
        case .git:
          gitTabContent
        case .shellInitScript:
          shellInitScriptContent
        }

        errorBanner
        buttonRow
      }
    }
    .padding(20)
    .frame(width: 440)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
  }

  // MARK: - Git Tab Content (4 cases)

  @ViewBuilder
  private var gitTabContent: some View {
    if isNewSessionFlow {
      if hasGitRepo {
        newSessionWithGitContent
      } else {
        newSessionNoGitContent
      }
    } else {
      if hasGitRepo {
        splitWithGitContent
      } else {
        splitNoGitContent
      }
    }
  }

  // MARK: Case A1: New session + no git

  private var newSessionNoGitContent: some View {
    VStack(spacing: 12) {
      HStack {
        Toggle("Initialize git", isOn: form.initGit)
          .font(.subheadline)
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .font(.subheadline)
          .help("Creates a git repository in this folder with an initial commit. Required for branch and worktree operations.")
      }

      if form.wrappedValue.initGit {
        HStack {
          Toggle("Create branch", isOn: form.createBranch)
            .font(.subheadline)
          Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .help("Creates a new git branch for this session. Allows working on a separate branch or in a dedicated worktree folder.")
        }

        if form.wrappedValue.createBranch {
          gitModeSegment
          branchOrWorktreeFields
        }
      }

      forkSessionToggle
    }
  }

  // MARK: Case A2: New session + git

  private var newSessionWithGitContent: some View {
    VStack(spacing: 12) {
      gitModeSegment
      branchOrWorktreeFields
      forkSessionToggle
    }
  }

  // MARK: Case B1: Split + no git

  private var splitNoGitContent: some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.yellow)
        Text("This folder is not a git repository.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        Toggle("Initialize git", isOn: form.initGit)
          .font(.subheadline)
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .font(.subheadline)
          .help("Creates a git repository in this folder with an initial commit. Required for branch and worktree operations.")
      }

      if form.wrappedValue.initGit {
        disabledGitModeSegment
        worktreeFields
      }
    }
  }

  // MARK: Case B2: Split + git

  private var splitWithGitContent: some View {
    VStack(spacing: 12) {
      disabledGitModeSegment
      worktreeFields
      forkSessionToggle
    }
  }

  // MARK: - Shared Git UI Components

  private var gitModeSegment: some View {
    Picker("", selection: form.gitMode) {
      ForEach(WorktreeSplitFormData.GitMode.allCases, id: \.self) { mode in
        Text(mode.rawValue).tag(mode)
      }
    }
    .pickerStyle(.segmented)
  }

  /// Segment with Branch disabled (for split flow).
  private var disabledGitModeSegment: some View {
    Picker("", selection: .constant(WorktreeSplitFormData.GitMode.worktree)) {
      Text("Branch").tag(WorktreeSplitFormData.GitMode.branch)
        .disabled(true)
      Text("Worktree").tag(WorktreeSplitFormData.GitMode.worktree)
    }
    .pickerStyle(.segmented)
    .disabled(true)
  }

  @ViewBuilder
  private var branchOrWorktreeFields: some View {
    switch form.wrappedValue.gitMode {
    case .branch:
      branchFields
    case .worktree:
      worktreeFields
    }
  }

  // MARK: Branch-only fields

  private var branchFields: some View {
    VStack(spacing: 12) {
      if hasGitRepo {
        HStack {
          Text("Current branch:")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text(form.wrappedValue.baseBranch)
            .font(.system(.subheadline, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        HStack {
          Toggle("Create new branch", isOn: form.createBranch)
            .font(.subheadline)
          Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .help("Check to start work on a new branch instead of the current one.")
        }
      }

      if form.wrappedValue.createBranch || !hasGitRepo {
        newBranchField
        baseBranchPicker
      }
    }
  }

  // MARK: Worktree fields

  private var worktreeFields: some View {
    VStack(spacing: 12) {
      newBranchField
      baseBranchPicker
      destinationField
      if form.wrappedValue.hasSubmodules {
        submoduleOptions
      }
    }
  }

  // MARK: - Shared Sub-views

  private var baseBranchPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Base branch")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if form.wrappedValue.availableBranches.isEmpty {
        TextField("Branch name", text: form.baseBranch)
          .textFieldStyle(.roundedBorder)
      } else {
        Picker("", selection: form.baseBranch) {
          ForEach(form.wrappedValue.availableBranches, id: \.self) { branch in
            Text(branch).tag(branch)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var newBranchField: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("New branch name")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      TextField("branch-name", text: form.newBranchName)
        .textFieldStyle(.roundedBorder)
        .onChange(of: form.wrappedValue.newBranchName) { _, newName in
          // Auto-update worktree path when branch name changes (only in worktree mode)
          if form.wrappedValue.gitMode == .worktree, let formData = viewModel.worktreeSplitForm {
            viewModel.worktreeSplitForm?.worktreePath =
              viewModel.appModel.gitService.defaultWorktreePath(repoRoot: formData.repoRoot, branchName: newName, sessionId: formData.tenvySessionId)
          }
        }
    }
  }

  private var destinationField: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Worktree destination")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        TextField("Path", text: form.worktreePath)
          .textFieldStyle(.roundedBorder)
          .truncationMode(.head)

        Button("Browse...") {
          browseDestination()
        }
      }
    }
  }

  @ViewBuilder
  private var forkSessionToggle: some View {
    if !form.wrappedValue.sourceIsNewSession {
      HStack {
        Toggle("Fork session", isOn: form.forkSession)
          .font(.subheadline)
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .font(.subheadline)
          .help("Preserves conversation history from the current session into the new one.")
      }
    }
  }

  private var submoduleOptions: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Submodule options")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack {
        Toggle("Initialize submodules", isOn: form.initSubmodules)
          .font(.subheadline)
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .font(.subheadline)
          .help("Runs \"git submodule update --init --recursive\" in the new worktree. Git worktrees don't automatically initialize submodules, so without this the worktree will have empty submodule directories.")
      }

      HStack {
        Toggle("Symlink build artifacts", isOn: form.symlinkBuildArtifacts)
          .font(.subheadline)
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .font(.subheadline)
          .help("Symlinks gitignored build artifacts (e.g. xcframeworks, compiled binaries) from the main repo's submodules into the worktree. This avoids having to rebuild them from source, which can be slow.")
      }
    }
  }

  // MARK: - Shell Init Script Tab

  private var shellInitScriptContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Bash script executed before launching the terminal session.")
        .font(.caption)
        .foregroundStyle(.secondary)

      CodeEditor(source: form.initScript, language: .bash, theme: .ocean)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6))

      HStack {
        Spacer()
        Button("Reset to Default") {
          form.wrappedValue.initScript = AppSettings.defaultShellInitScript
        }
        .font(.caption)
        .disabled(form.wrappedValue.initScript == AppSettings.defaultShellInitScript)
      }
    }
  }

  // MARK: - Plain Terminal Split

  private var plainTerminalSplitHeader: some View {
    HStack {
      Image(systemName: "terminal")
        .font(.title2)
        .foregroundStyle(.blue)

      Text("New Terminal")
        .font(.headline)

      Spacer()

      Button {
        viewModel.cancelSplitDialog()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
  }

  private var plainTerminalButtonRow: some View {
    HStack(spacing: 12) {
      Button("Cancel") {
        viewModel.cancelSplitDialog()
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)

      Spacer()

      Button("Create") {
        viewModel.openPlainTerminalSplit(
          initScript: form.wrappedValue.initScript,
          asPlainTerminal: true
        )
      }
      .buttonStyle(.borderedProminent)
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      if hasGitRepo {
        Image(systemName: "arrow.triangle.branch")
          .font(.title2)
          .foregroundStyle(.orange)
      } else {
        Image(systemName: "exclamationmark.triangle")
          .font(.title2)
          .foregroundStyle(.yellow)
      }

      Text(headerTitle)
        .font(.headline)

      Spacer()

      Button {
        viewModel.cancelSplitDialog()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
  }

  private var headerTitle: String {
    if isNewSessionFlow {
      return hasGitRepo ? "New Session" : "New Session"
    } else {
      return hasGitRepo ? "Create Split" : "Create Split"
    }
  }

  // MARK: - Error Banner

  @ViewBuilder
  private var errorBanner: some View {
    if let error = viewModel.worktreeError {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.red.opacity(0.1))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  // MARK: - Button Row

  private var buttonRow: some View {
    HStack(spacing: 12) {
      Button("Cancel") {
        viewModel.cancelSplitDialog()
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)

      Spacer()

      Button("Terminal Only") {
        viewModel.openPlainTerminalSplit(
          initScript: form.wrappedValue.initScript,
          asPlainTerminal: true
        )
      }
      .buttonStyle(.bordered)

      Button {
        viewModel.confirmNewSessionDialog()
      } label: {
        if viewModel.isCreatingWorktree {
          ProgressView()
            .controlSize(.small)
            .padding(.horizontal, 8)
        } else {
          Text("Start")
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(startDisabled)
      .help(startDisabledTooltip)
    }
  }

  // MARK: - Button Enablement

  private var startDisabled: Bool {
    if viewModel.isCreatingWorktree { return true }

    // Split + no git + init unchecked → must configure git
    if !isNewSessionFlow && !hasGitRepo && !form.wrappedValue.initGit {
      return true
    }

    // Worktree mode selected but branch name empty
    if isWorktreeActive && form.wrappedValue.newBranchName.isEmpty {
      return true
    }

    // Branch mode with createBranch checked but name empty
    if isBranchCreationActive && form.wrappedValue.newBranchName.isEmpty {
      return true
    }

    // Split + no git + init checked but worktree name empty
    if !isNewSessionFlow && !hasGitRepo && form.wrappedValue.initGit && form.wrappedValue.newBranchName.isEmpty {
      return true
    }

    return false
  }

  private var startDisabledTooltip: String {
    if !isNewSessionFlow && !hasGitRepo && !form.wrappedValue.initGit {
      return "Running two sessions on the same folder without git causes file collisions. Initialize git and configure a worktree to proceed."
    }
    return ""
  }

  /// Whether worktree fields are currently active and need to be filled.
  private var isWorktreeActive: Bool {
    let f = form.wrappedValue
    if !isNewSessionFlow && hasGitRepo { return true } // split + git → always worktree
    if !isNewSessionFlow && !hasGitRepo && f.initGit { return true } // split + no git + init
    if f.gitMode == .worktree {
      if hasGitRepo { return true }
      if f.initGit && f.createBranch { return true }
    }
    return false
  }

  /// Whether branch creation fields are active and need a name.
  private var isBranchCreationActive: Bool {
    let f = form.wrappedValue
    return f.gitMode == .branch && f.createBranch
  }

  // MARK: - Actions

  private func browseDestination() {
    let panel = NSOpenPanel()
    panel.title = "Choose worktree destination"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      viewModel.worktreeSplitForm?.worktreePath = url.path
    }
  }
}

#Preview("New Session + Git") {
  NewSessionDialogView(viewModel: ContentViewModel(appModel: AppModel()))
}
