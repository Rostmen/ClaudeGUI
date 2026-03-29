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

/// Dialog shown when user triggers a split in a git-controlled session.
/// Lets the user configure a worktree: base branch, new branch name, destination, and fork toggle.
struct WorktreeSplitView: View {
  @Bindable var viewModel: ContentViewModel

  private var form: Binding<WorktreeSplitFormData> {
    Binding(
      get: { viewModel.worktreeSplitForm ?? WorktreeSplitFormData(
        baseBranch: "", newBranchName: "", worktreePath: "",
        forkSession: false, availableBranches: [],
        sourceSessionId: "", sourceIsNewSession: true, repoRoot: ""
      )},
      set: { viewModel.worktreeSplitForm = $0 }
    )
  }

  var body: some View {
    VStack(spacing: 16) {
      header
      baseBranchPicker
      newBranchField
      destinationField
      forkSessionToggle
      errorBanner
      buttonRow
    }
    .padding(20)
    .frame(width: 440)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
  }

  // MARK: - Subviews

  private var header: some View {
    HStack {
      Image(systemName: "arrow.triangle.branch")
        .font(.title2)
        .foregroundStyle(.orange)

      Text("Create Worktree Split")
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
          // Auto-update worktree path when branch name changes
          if let formData = viewModel.worktreeSplitForm {
            viewModel.worktreeSplitForm?.worktreePath =
              WorktreeService.defaultWorktreePath(repoRoot: formData.repoRoot, branchName: newName)
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
      Toggle("Fork current session", isOn: form.forkSession)
        .font(.subheadline)
        .help("Creates a new session preserving conversation history from the current session")
    }
  }

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

  private var buttonRow: some View {
    HStack(spacing: 12) {
      Button("Cancel") {
        viewModel.cancelSplitDialog()
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)

      Spacer()

      Button("Plain Terminal") {
        viewModel.openPlainTerminalSplit()
      }
      .buttonStyle(.bordered)

      Button {
        viewModel.confirmWorktreeSplit()
      } label: {
        if viewModel.isCreatingWorktree {
          ProgressView()
            .controlSize(.small)
            .padding(.horizontal, 8)
        } else {
          Text("Create Worktree")
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.isCreatingWorktree || form.wrappedValue.newBranchName.isEmpty)
    }
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
