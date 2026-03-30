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
import CodeEditor

/// Dialog shown when user triggers a split in a non-git directory.
/// Offers to initialize git + create worktree, or open a plain terminal.
struct NoGitSplitView: View {
  let viewModel: ContentViewModel
  @State private var selectedTab: SplitTab = .options
  @State private var initScript: String = AppSettings.shared.shellInitScript

  private enum SplitTab: String, CaseIterable {
    case options = "Options"
    case terminal = "Terminal"
  }

  var body: some View {
    VStack(spacing: 16) {
      header

      Picker("", selection: $selectedTab) {
        ForEach(SplitTab.allCases, id: \.self) { tab in
          Text(tab.rawValue).tag(tab)
        }
      }
      .pickerStyle(.segmented)

      switch selectedTab {
      case .options:
        optionsContent
      case .terminal:
        terminalContent
      }

      errorBanner

      if viewModel.isCreatingWorktree {
        ProgressView("Initializing repository...")
          .controlSize(.small)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      buttonRow
    }
    .padding(20)
    .frame(width: 440)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
  }

  // MARK: - Tab Content

  private var optionsContent: some View {
    Text("Running parallel Claude sessions on the same files can cause collisions. Choose how to proceed:")
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var terminalContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Shell Init Script")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      CodeEditor(source: $initScript, language: .bash, theme: .ocean)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6))

      HStack {
        Spacer()
        Button("Reset to Default") {
          initScript = AppSettings.defaultShellInitScript
        }
        .font(.caption)
        .disabled(initScript == AppSettings.defaultShellInitScript)
      }
    }
  }

  // MARK: - Subviews

  private var header: some View {
    HStack {
      Image(systemName: "exclamationmark.triangle")
        .font(.title2)
        .foregroundStyle(.yellow)

      Text("No Git Repository")
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

      Button("Open Plain Terminal") {
        viewModel.openPlainTerminalSplit(initScript: initScript)
      }
      .buttonStyle(.bordered)

      Button("Initialize Git & Create Worktree") {
        viewModel.initGitAndCreateWorktree()
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.isCreatingWorktree)
    }
  }
}
