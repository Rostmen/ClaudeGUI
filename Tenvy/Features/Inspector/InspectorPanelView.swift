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

/// Right-side inspector panel showing details about the focused session or terminal.
/// Available only in DEBUG builds.
struct InspectorPanelView: View {
  let session: ClaudeSession
  let runtimeInfo: SessionRuntimeInfo

  @State private var availableBranches: [String] = []
  @State private var branchError: String?
  @State private var showBranchError = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        branchSection
        pathsSection
      }
      .padding(12)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear { loadBranches() }
    .onChange(of: session.id) { _, _ in loadBranches() }
    .alert("Branch Switch Failed", isPresented: $showBranchError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(branchError ?? "Unknown error")
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private var branchSection: some View {
    if let currentBranch = runtimeInfo.gitBranch {
      InspectorSection("Branch") {
        Picker(selection: Binding(
          get: { currentBranch },
          set: { switchBranch(to: $0) }
        )) {
          Text(currentBranch).tag(currentBranch)
          if !availableBranches.isEmpty {
            Divider()
            ForEach(availableBranches, id: \.self) { branch in
              Text(branch).tag(branch)
            }
          }
        } label: {
          EmptyView()
        }
        .labelsHidden()
      }
    }
  }

  @ViewBuilder
  private var pathsSection: some View {
    InspectorSection("Paths") {
      InspectorPathRow("Working Dir", path: session.workingDirectory)
      InspectorPathRow("Project", path: session.projectPath)
    }
  }

  // MARK: - Branch Logic

  private func loadBranches() {
    let path = session.workingDirectory
    let all = GitBranchService.listLocalBranches(at: path)
    let worktree = GitBranchService.worktreeBranches(at: path)
    let current = runtimeInfo.gitBranch ?? ""
    availableBranches = all.filter { $0 != current && !worktree.contains($0) }
  }

  private func switchBranch(to branch: String) {
    let error = GitBranchService.checkoutBranch(branch, at: session.workingDirectory)
    if let error {
      branchError = error
      showBranchError = true
    } else {
      runtimeInfo.gitBranch = branch
      loadBranches()
    }
  }
}

// MARK: - Inspector Section

private struct InspectorSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content

  init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)

      VStack(alignment: .leading, spacing: 4) {
        content()
      }
    }
  }
}

// MARK: - Inspector Path Row

private struct InspectorPathRow: View {
  let label: String
  let path: String
  @State private var isHovered = false

  init(_ label: String, path: String) {
    self.label = label
    self.path = path
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.tertiary)

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(abbreviatedPath)
          .font(.caption)
          .fontDesign(.monospaced)
          .textSelection(.enabled)
          .lineLimit(2)
        Spacer()
        Button {
          NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } label: {
          Image(systemName: isHovered ? "folder.fill" : "folder")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Reveal in Finder")
      }
    }
  }

  private var abbreviatedPath: String {
    path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
  }
}

#Preview("With Session") {
  @Previewable @State var session = ClaudeSession(
    id: "preview-123",
    title: "Implement feature",
    projectPath: "/Users/dev/Projects/MyApp/Sources/MyApp/Directories/Inspector",
    workingDirectory: "/Users/dev/Projects/MyApp",
    lastModified: Date(),
    filePath: nil
  )
  let info: SessionRuntimeInfo = {
    let info = SessionRuntimeInfo()
    info.gitBranch = "feature/inspector"
    return info
  }()
  InspectorPanelView(
    session: session,
    runtimeInfo: info
  )
  .frame(width: 260, height: 400)
  .background(.ultraThinMaterial)
}
