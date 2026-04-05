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
import GRDB
import GRDBQuery

/// Right-side inspector panel showing details about the focused session or terminal.
struct InspectorPanelView: View {

  /// Actions emitted by the inspector for the parent to handle.
  enum Action {
    /// User requested restarting the session with updated permission settings.
    case restartWithNewPermissions(sessionId: String)
  }

  let session: ClaudeSession
  let runtimeInfo: SessionRuntimeInfo
  var onAction: (Action) -> Void = { _ in }

  @Environment(AppModel.self) private var appModel

  /// Reactively observes the session record in DB — permission hash changes
  /// (e.g. after restart) are picked up automatically without generation counters.
  @Query<SessionByTenvyIdRequest> private var sessionRecord: SessionRecord?

  @State private var availableBranches: [String] = []
  @State private var branchError: String?
  @State private var showBranchError = false
  @State private var sessionPermissions = ClaudePermissionSettings.empty
  @State private var permissionsLoaded = false
  @State private var showPermissionRestartWarning = false
  @State private var showRestartConfirmation = false

  init(session: ClaudeSession, runtimeInfo: SessionRuntimeInfo, onAction: @escaping (Action) -> Void = { _ in }) {
    self.session = session
    self.runtimeInfo = runtimeInfo
    self.onAction = onAction
    _sessionRecord = Query(SessionByTenvyIdRequest(tenvySessionId: session.tenvySessionId))
  }

  /// Whether this is a plain terminal (from DB record).
  private var isPlainTerminal: Bool {
    sessionRecord?.isPlainTerminal ?? false
  }

  /// SHA-256 hash of the permissions when the session was last launched.
  private var launchedPermissionsHash: String {
    sessionRecord?.launchedPermissionsHash ?? ""
  }

  /// True when the current permissions differ from what the session launched with.
  private var permissionSettingsModified: Bool {
    !launchedPermissionsHash.isEmpty && sessionPermissions.contentHash != launchedPermissionsHash
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        branchSection
        pathsSection
        if !isPlainTerminal {
          permissionsSection
        }
      }
      .padding(12)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear {
      loadBranches()
      loadPermissions()
    }
    .onChange(of: session.id) { _, _ in
      loadBranches()
      loadPermissions()
    }
    .onChange(of: sessionRecord?.launchedPermissionsHash) { _, _ in
      // DB record updated (e.g. after restart) — hide the restart warning
      // since launchedPermissionsHash now matches the current permissions.
      showPermissionRestartWarning = false
    }
    .onChange(of: sessionPermissions) { _, newValue in
      guard permissionsLoaded else { return }
      savePermissions(newValue)
    }
    .alert("Branch Switch Failed", isPresented: $showBranchError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(branchError ?? "Unknown error")
    }
    .alert("Restart Session?", isPresented: $showRestartConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Restart", role: .destructive) {
        onAction(.restartWithNewPermissions(sessionId: session.id))
      }
    } message: {
      Text("This will terminate the current session and restart it with the updated permissions.")
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

  // MARK: - Permissions Section

  @ViewBuilder
  private var permissionsSection: some View {
    InspectorSection("Permissions") {
      HStack {
        Image(systemName: permissionSettingsModified ? "pencil.circle.fill" : "arrow.down.circle.fill")
          .font(.caption2)
          .foregroundStyle(permissionSettingsModified ? .orange : .secondary)
        Text(permissionSettingsModified ? "Customized" : "Inherited from Global + Project")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if showPermissionRestartWarning {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(.orange.opacity(0.7))
          Text("Permission changes take effect after restart")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
      }

      PermissionEditorView(settings: $sessionPermissions)

      if permissionSettingsModified {
        Button {
          showRestartConfirmation = true
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
            Text("Restart with New Permissions")
          }
          .font(.caption)
          .foregroundStyle(.orange)
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }

      Button {
        resetPermissions()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "arrow.uturn.backward")
          Text("Reset to Inherited")
        }
        .font(.caption)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
    }
  }

  // MARK: - Permission Logic

  private func loadPermissions() {
    permissionsLoaded = false

    if let record = sessionRecord,
       let stored = record.decodedPermissionSettings {
      sessionPermissions = stored
    } else {
      sessionPermissions = ClaudeSettingsService.mergeForNewSession(projectPath: session.projectPath)
    }

    showPermissionRestartWarning = false
    permissionsLoaded = true
  }

  private func savePermissions(_ settings: ClaudePermissionSettings) {
    try? appModel.sessionStore.updatePermissionSettings(
      tenvySessionId: session.tenvySessionId,
      settings: settings
    )
    if permissionSettingsModified {
      showPermissionRestartWarning = true
    }
  }

  private func resetPermissions() {
    permissionsLoaded = false
    try? appModel.sessionStore.resetPermissionSettings(tenvySessionId: session.tenvySessionId)
    sessionPermissions = ClaudeSettingsService.mergeForNewSession(projectPath: session.projectPath)
    // launchedPermissionsHash is now a computed property from sessionRecord (via @Query) —
    // resetPermissionSettings clears it in DB, and the @Query observation picks up the change.
    showPermissionRestartWarning = false
    permissionsLoaded = true
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
    runtimeInfo: info,
    onAction: { action in print("Inspector action: \(action)") }
  )
  .frame(width: 260, height: 600)
  .background(.ultraThinMaterial)
  .environment(AppModel())
}
