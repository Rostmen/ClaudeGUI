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
import UniformTypeIdentifiers
import GhosttyEmbed
import GRDBQuery

// MARK: - Preference Key for Terminal Frame
struct TerminalFrameKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    let next = nextValue()
    if value == .zero { value = next }
    else if next != .zero { value = value.union(next) }
  }
}

let kWindowOpacity: CGFloat = 0.5

struct ContentView: View {
  @Environment(\.colorScheme) private var colorScheme
  @State private var viewModel: ContentViewModel

  init(appModel: AppModel) {
    _viewModel = State(initialValue: ContentViewModel(appModel: appModel))
  }

  // Delegate prompt visibility to the ViewModel (which reads from appModel services)
  private var hookPromptVisible: Bool { viewModel.hookPromptVisible }
  private var notificationPromptVisible: Bool { viewModel.notificationPromptVisible }
  private var updatePromptVisible: Bool { viewModel.updatePromptVisible }

  // UI-only state
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var terminalFrame: CGRect = .zero
  @State private var currentWindow: NSWindow?
  @State private var showHookPrompt: Bool = false
  @State private var showNotificationPrompt: Bool = false
  @State private var showUpdatePrompt: Bool = false
  @State private var updateDismissTimer: Timer?

  private var selectedSessionBinding: Binding<ClaudeSession?> {
    Binding(
      get: { viewModel.selectedSession },
      set: { _ in } // Read-only — use viewModel.selectSession instead
    )
  }

  @ViewBuilder
  private var navigationContent: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      SidebarView(
        sessionManager: viewModel.sessionDiscovery,
        selectedSession: selectedSessionBinding,
        selectedDiffFile: $viewModel.selectedDiffFile,
        onAction: { viewModel.handleSessionListAction($0) },
        runtimeState: viewModel.runtimeState,
        activeSessionIds: viewModel.activeSessionIds,
        activatedSessions: viewModel.activatedSessions,
        splitSessionIds: viewModel.splitSessionIds,
        plainTerminalTitles: viewModel.plainTerminalTitles
      )
      .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
    } detail: {
      DetailView(
        viewModel: viewModel,
        terminalFramePreferenceKey: TerminalFrameKey.self
      )
    }
    .navigationTitle(viewModel.selectedSession?.title ?? "Select or start a new session")
    .inspector(isPresented: $viewModel.showInspectorPanel) {
      if let session = viewModel.selectedSession {
        InspectorPanelView(
          session: session,
          runtimeInfo: viewModel.runtimeState.info(for: session.id)
        )
        .inspectorColumnWidth(min: 200, ideal: 260, max: 360)
      }
    }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          viewModel.showInspectorPanel.toggle()
        } label: {
          Image(systemName: "sidebar.trailing")
        }
        .help("Toggle Inspector (⌘⌥I)")
      }
    }
  }

  var body: some View {
    ZStack {
      VisualEffectBackground()
        .ignoresSafeArea()

      // Captures the window reference
      WindowAccessor(window: $currentWindow)
        .frame(width: 0, height: 0)

      // Dark overlay with cutout for terminal
      DarkOverlayCanvas(terminalFrame: terminalFrame)
        .allowsHitTesting(false)
        .ignoresSafeArea()

      navigationContent

      // Worktree split dialog overlay (centered, with dim backdrop)
      if viewModel.pendingSplit != nil {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .onTapGesture { viewModel.cancelSplitDialog() }

        NewSessionDialogView(viewModel: viewModel)
          .transition(.opacity)
      }
    }
    .coordinateSpace(name: "window")
    .overlay(alignment: .bottomTrailing) {
      // Notification permission prompt overlay
      if showNotificationPrompt {
        NotificationPermissionPromptView {
          showNotificationPrompt = false
        }
        .frame(maxWidth: 420)
        .padding(24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .overlay(alignment: .bottomTrailing) {
      // Hook installation prompt overlay (only when notification prompt is not showing)
      if showHookPrompt && !showNotificationPrompt {
        HookInstallationPromptView {
          showHookPrompt = false
        }
        .frame(maxWidth: 420)
        .padding(24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .overlay(alignment: .bottomTrailing) {
      // Update available prompt overlay (only when no other prompt is showing)
      if showUpdatePrompt && !showNotificationPrompt && !showHookPrompt {
        UpdatePromptView {
          showUpdatePrompt = false
        }
        .frame(maxWidth: 420)
        .padding(24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear { startUpdateDismissTimer() }
        .onDisappear { updateDismissTimer?.invalidate() }
      }
    }
    .onPreferenceChange(TerminalFrameKey.self) { frame in
      terminalFrame = frame
    }
    .preferredColorScheme(AppSettings.shared.appearanceMode.colorScheme)
    .onChange(of: colorScheme) { _, _ in
      // Re-sync Claude theme when system appearance changes (relevant for System mode)
      if AppSettings.shared.appearanceMode == .system {
        ClaudeThemeSync.apply(.system)
      }
    }
    .onAppear {
      viewModel.handleAppear()
    }
    .task {
      // Periodically refresh git branches (reads .git/HEAD — microsecond filesystem op)
      while !Task.isCancelled {
        viewModel.appModel.refreshGitBranches()
        try? await Task.sleep(for: .seconds(5))
      }
    }
    .onChange(of: currentWindow) { _, newWindow in
      viewModel.setWindow(newWindow)
      newWindow?.title = viewModel.selectedSession?.title ?? "Select or start a new session"
    }
    .onChange(of: viewModel.selectedSession) { _, session in
      currentWindow?.title = session?.title ?? "Select or start a new session"
    }
    // Session data (titles, hookState) is observed via @Query from the DB.
    // Session ID sync is driven by hook events (AppModel.syncSessionFromHookEvent).
    .onChange(of: hookPromptVisible) { _, shouldShow in
      withAnimation(.easeInOut(duration: 0.3)) {
        showHookPrompt = shouldShow
      }
    }
    .onChange(of: notificationPromptVisible) { _, shouldShow in
      withAnimation(.easeInOut(duration: 0.3)) {
        showNotificationPrompt = shouldShow
      }
    }
    .onChange(of: updatePromptVisible) { _, shouldShow in
      withAnimation(.easeInOut(duration: 0.3)) {
        showUpdatePrompt = shouldShow
      }
    }
    .alert("Rename", isPresented: Binding(
      get: { viewModel.sessionToRename != nil },
      set: { if !$0 { viewModel.sessionToRename = nil } }
    )) {
      TextField("Name", text: $viewModel.renameText)
      Button("Cancel", role: .cancel) { viewModel.sessionToRename = nil }
      Button("Rename") { viewModel.commitRename() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .toggleInspectorPanel)) { _ in
      withAnimation(.easeInOut(duration: 0.2)) {
        viewModel.showInspectorPanel.toggle()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .openSessionFromNotification)) { notification in
      if let session = notification.object as? ClaudeSession {
        // If session is already open in another window, just focus that window
        if viewModel.appModel.windowRegistry.selectSession(session.id, currentWindow: viewModel.currentWindow) {
          return
        }
        // Only open here if this window has no session yet
        guard viewModel.selectedSession == nil else { return }
        viewModel.selectSession(session)
      }
    }
  }

  private func startUpdateDismissTimer() {
    updateDismissTimer?.invalidate()
    updateDismissTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
      DispatchQueue.main.async {
        // Only auto-dismiss in idle state (not while installing/failed)
        guard viewModel.appModel.updater.updateState == .idle else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
          showUpdatePrompt = false
        }
      }
    }
  }
}

// MARK: - Dark Overlay Canvas

private struct DarkOverlayCanvas: View {
  let terminalFrame: CGRect
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Canvas { context, size in
      let overlayColor: Color = colorScheme == .dark
        ? .black.opacity(kWindowOpacity)
        : .white.opacity(0.55)
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(overlayColor)
      )
      if terminalFrame != .zero {
        context.blendMode = .destinationOut
        context.fill(Path(terminalFrame), with: .color(.white))
      }
    }
  }
}

// MARK: - Detail View

private struct DetailView<Key: PreferenceKey>: View where Key.Value == CGRect {
  let viewModel: ContentViewModel
  let terminalFramePreferenceKey: Key.Type

  /// Drives the SwiftUI `.onDrop` `isTargeted` for single-pane mode.
  /// Synced to `viewModel.fileDropTargetTerminalId` via `onChange`.
  @State private var isSinglePaneDropTargeted = false

  var body: some View {
    ZStack {
      if viewModel.isInSplitMode, let tree = viewModel.splitTree {
        // Split mode: GhosttyHostView handles file drops at the AppKit level.
        // Drag enter/exit/drop fire TerminalAction callbacks → PaneLeafView
        // updates highlight + focus per-pane.
        PaneSplitTreeRenderer(node: tree.root, viewModel: viewModel)
          .background(terminalFrameReader(visible: true))
          .padding(16)
      } else if let session = viewModel.selectedSession,
                viewModel.shouldRenderTerminal(for: session) {
        // Single-pane mode: SwiftUI's hosting layer blocks AppKit drag events
        // from reaching GhosttyHostView. Use SwiftUI .onDrop as fallback,
        // applied after .allowsHitTesting() to avoid being blocked.
        PaneLeafView(session: session, viewModel: viewModel, isSplitPane: false)
          .id(session.terminalId)
          .opacity(viewModel.isTerminalVisible ? 1 : 0)
          .allowsHitTesting(viewModel.isTerminalVisible)
          .onDrop(of: [.fileURL], isTargeted: $isSinglePaneDropTargeted) { providers in
            viewModel.handleSinglePaneFileDrop(providers: providers, terminalId: session.terminalId)
          }
          .onChange(of: isSinglePaneDropTargeted) { _, targeted in
            viewModel.fileDropTargetTerminalId = targeted ? session.terminalId : nil
          }
          .background(terminalFrameReader(visible: viewModel.isTerminalVisible))
          .padding(16)
      }

      // Diff View (shown when diff file is selected)
      if let diffFile = viewModel.selectedDiffFile {
        DiffView(file: diffFile)
          .padding(16)
          .background(terminalFrameReader(visible: true))
      }

      if viewModel.showEmptyState {
        EmptyTerminalView()
      }
    }
  }

  @ViewBuilder
  private func terminalFrameReader(visible: Bool) -> some View {
    GeometryReader { geo in
      Color.clear.preference(
        key: terminalFramePreferenceKey,
        value: visible ? geo.frame(in: .named("window")) : .zero
      )
    }
  }
}

// MARK: - PaneSplitTreeRenderer

/// Recursively renders a `PaneSplitTree` using `PaneSplitView` for splits
/// and `TerminalView` for leaves.  Mirrors `TerminalSplitTreeView` from Ghostty.
private struct PaneSplitTreeRenderer: View {
  let node: PaneSplitTree.Node
  let viewModel: ContentViewModel

  var body: some View {
    treeContent
  }

  @ViewBuilder
  private var treeContent: some View {
    switch node {
    case .leaf(let session):
      leafView(session: session)
    case .split(let split):
      splitView(split: split)
    }
  }

  @ViewBuilder
  private func splitView(split: PaneSplitTree.Split) -> some View {
    PaneSplitView(
      split.direction,
      .init(
        get: { CGFloat(split.ratio) },
        set: { viewModel.updateSplitRatio(splitId: split.id, ratio: Double($0)) }
      )
    ) {
      PaneSplitTreeRenderer(node: split.left, viewModel: viewModel)
    } right: {
      PaneSplitTreeRenderer(node: split.right, viewModel: viewModel)
    }
  }

  @ViewBuilder
  private func leafView(session: ClaudeSession) -> some View {
    if viewModel.shouldRenderTerminal(for: session) {
      PaneLeafView(session: session, viewModel: viewModel, isSplitPane: true)
    }
  }
}

// MARK: - PaneLeafView

/// Wraps a terminal view with a header bar and drop zone overlay.
/// Used in both single-pane mode (DetailView) and split mode (PaneSplitTreeRenderer).
private struct PaneLeafView: View {
  let session: ClaudeSession
  let viewModel: ContentViewModel
  var isSplitPane: Bool = false

  /// DB-backed session record — provides hookState from the persistent store.
  @Query<SessionByTerminalIdRequest> private var sessionRecord: SessionRecord?
  @State private var dropZone: PaneDropZone?

  init(session: ClaudeSession, viewModel: ContentViewModel, isSplitPane: Bool = false) {
    self.session = session
    self.viewModel = viewModel
    self.isSplitPane = isSplitPane
    _sessionRecord = Query(SessionByTerminalIdRequest(terminalId: session.terminalId))
  }

  private var isClaudeSession: Bool {
    !viewModel.isPlainTerminal(session.terminalId)
  }

  private var isFileDropTargeted: Bool {
    viewModel.fileDropTargetTerminalId == session.terminalId
  }

  /// Reactive title: prefers DB record, falls back to session manager, then session struct.
  private var paneTitle: String {
    if viewModel.isPlainTerminal(session.terminalId) {
      return viewModel.plainTerminalTitles[session.terminalId] ?? "Terminal"
    }
    if let dbTitle = sessionRecord?.title, dbTitle != "New Session" {
      return dbTitle
    }
    if let updated = viewModel.sessionDiscovery.sessions.first(where: { $0.id == session.id }) {
      return updated.title
    }
    return session.title
  }

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        PaneHeaderView(
          title: paneTitle,
          terminalId: session.terminalId,
          isSelected: viewModel.selectedSession?.id == session.id,
          isFileDropTarget: isFileDropTargeted,
          runtimeInfo: viewModel.runtimeState.info(for: session.id),
          sessionRecord: sessionRecord,
          isActive: viewModel.appModel.isSessionActivated(session.id),
          ideResult: isClaudeSession ? viewModel.ideDetectionResult(for: session) : nil,
          projectPath: isClaudeSession ? (session.workingDirectory.isEmpty ? session.projectPath : session.workingDirectory) : nil,
          snapshotProvider: { [weak viewModel] in
            viewModel?.ghosttyHostView(for: session.terminalId)?.snapshotImage
          },
          onAction: { action in
            switch action {
            case .closeRequested:
              viewModel.closePaneByTerminalId(session.terminalId)
            }
          }
        )

        ZStack {
          terminalView

          if let zone = dropZone {
            zone.overlay(in: geometry.size)
              .allowsHitTesting(false)
          }
        }
      }
      .onDrop(of: [.tenvyPaneId], delegate: PaneDropDelegate(
        destinationTerminalId: session.terminalId,
        dropZone: $dropZone,
        viewSize: geometry.size,
        headerHeight: 30,
        viewModel: viewModel
      ))
    }
  }

  private func handleAction(_ action: TerminalAction) {
    switch action {
    case .fileDragEntered:
      viewModel.fileDropTargetTerminalId = session.terminalId
    case .fileDragExited:
      if viewModel.fileDropTargetTerminalId == session.terminalId {
        viewModel.fileDropTargetTerminalId = nil
      }
    case .fileDropped:
      viewModel.fileDropTargetTerminalId = nil
      viewModel.focusPane(terminalId: session.terminalId)
    default:
      if isSplitPane {
        viewModel.handleSplitTerminalAction(action, for: session)
      } else {
        viewModel.handleTerminalAction(action, for: session)
      }
    }
  }

  @ViewBuilder
  private var terminalView: some View {
    if viewModel.isPlainTerminal(session.terminalId) {
      PlainTerminalView(
        workingDirectory: session.workingDirectory,
        isSelected: viewModel.selectedSession?.id == session.id,
        initScript: viewModel.initScript(for: session.terminalId),
        onAction: { action in
          handleAction(action)
        },
        existingHostView: viewModel.ghosttyHostView(for: session.terminalId),
        onHostViewCreated: { viewModel.cacheGhosttyHostView($0, terminalId: session.terminalId) }
      )
      .id(session.terminalId)
    } else {
      ClaudeSessionTerminalView(
        session: session,
        isSelected: viewModel.selectedSession?.id == session.id,
        forkSourceSessionId: viewModel.forkSourceSessionId(for: session.terminalId),
        initScript: viewModel.initScript(for: session.terminalId),
        onAction: { action in
          handleAction(action)
        },
        existingHostView: viewModel.ghosttyHostView(for: session.terminalId),
        onHostViewCreated: { viewModel.cacheGhosttyHostView($0, terminalId: session.terminalId) }
      )
      .id(session.terminalId)
    }
  }
}

// MARK: - PaneDropDelegate

/// SwiftUI DropDelegate that calculates drop zones and triggers pane moves.
private struct PaneDropDelegate: DropDelegate {
  let destinationTerminalId: String
  @Binding var dropZone: PaneDropZone?
  let viewSize: CGSize
  let headerHeight: CGFloat
  let viewModel: ContentViewModel

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [.tenvyPaneId])
  }

  func dropEntered(info: DropInfo) {
    updateZone(at: info.location)
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard dropZone != nil else { return DropProposal(operation: .forbidden) }
    updateZone(at: info.location)
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    dropZone = nil
  }

  func performDrop(info: DropInfo) -> Bool {
    let zone = PaneDropZone.calculate(at: adjustedPoint(info.location), in: viewSize)
    dropZone = nil

    guard let item = info.itemProviders(for: [.tenvyPaneId]).first else { return false }

    item.loadItem(forTypeIdentifier: "com.tenvy.paneId", options: nil) { data, _ in
      guard let data = data as? Data,
            let sourceTerminalId = String(data: data, encoding: .utf8) else { return }
      guard sourceTerminalId != destinationTerminalId else { return }

      DispatchQueue.main.async {
        viewModel.movePaneToSplit(
          sourceTerminalId: sourceTerminalId,
          destinationTerminalId: destinationTerminalId,
          zone: zone
        )
      }
    }
    return true
  }

  private func updateZone(at point: CGPoint) {
    dropZone = PaneDropZone.calculate(at: adjustedPoint(point), in: viewSize)
  }

  /// Adjust drop point to account for header height offset.
  private func adjustedPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x, y: max(0, point.y - headerHeight))
  }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = .active
    view.isEmphasized = true
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#Preview {
  ContentView(appModel: AppModel())
}
