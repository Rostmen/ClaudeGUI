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

// MARK: - Preference Key for Terminal Frame
struct TerminalFrameKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    let next = nextValue()
    if next != .zero {
      value = next
    }
  }
}

let kWindowOpacity: CGFloat = 0.5

struct ContentView: View {
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
        onCreateNewSession: { viewModel.createNewSession($0) },
        onSelectSession: { viewModel.selectSession($0) },
        runtimeState: viewModel.runtimeState,
        activeSessionIds: viewModel.activeSessionIds,
        activatedSessions: viewModel.activatedSessions
      )
      .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
    } detail: {
      DetailView(
        viewModel: viewModel,
        terminalFramePreferenceKey: TerminalFrameKey.self
      )
    }
    .navigationTitle(viewModel.selectedSession?.title ?? "Select or start a new session")
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

      // Notification permission prompt overlay
      if showNotificationPrompt {
        VStack {
          Spacer()
          HStack {
            Spacer()
            NotificationPermissionPromptView {
              showNotificationPrompt = false
            }
            .frame(maxWidth: 420)
            .padding(24)
          }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }

      // Hook installation prompt overlay (only when notification prompt is not showing)
      if showHookPrompt && !showNotificationPrompt {
        VStack {
          Spacer()
          HStack {
            Spacer()
            HookInstallationPromptView {
              showHookPrompt = false
            }
            .frame(maxWidth: 420)
            .padding(24)
          }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }

      // Update available prompt overlay (only when no other prompt is showing)
      if showUpdatePrompt && !showNotificationPrompt && !showHookPrompt {
        VStack {
          Spacer()
          HStack {
            Spacer()
            UpdatePromptView {
              showUpdatePrompt = false
            }
            .frame(maxWidth: 420)
            .padding(24)
          }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .coordinateSpace(name: "window")
    .onPreferenceChange(TerminalFrameKey.self) { frame in
      terminalFrame = frame
    }
    .preferredColorScheme(.dark)
    .onAppear {
      viewModel.handleAppear()
    }
    .onChange(of: currentWindow) { _, newWindow in
      viewModel.setWindow(newWindow)
      newWindow?.title = viewModel.selectedSession?.title ?? "Select or start a new session"
    }
    .onChange(of: viewModel.selectedSession) { _, session in
      currentWindow?.title = session?.title ?? "Select or start a new session"
    }
    .onChange(of: viewModel.sessionDiscovery.sessions) { _, _ in
      // When sessions reload, sync new sessions with Claude-created ones
      viewModel.syncNewSessionWithDiscoveredSession()
    }
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
}

// MARK: - Dark Overlay Canvas

private struct DarkOverlayCanvas: View {
  let terminalFrame: CGRect

  var body: some View {
    Canvas { context, size in
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(.black.opacity(kWindowOpacity))
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

  var body: some View {
    ZStack {
      // Terminal for this window's selected session only
      if let session = viewModel.selectedSession,
         viewModel.shouldRenderTerminal(for: session) {
        TerminalView(
          session: session,
          isSelected: viewModel.isTerminalVisible,
          onStateChange: { info in
            // Use current session ID (may have changed after sync)
            let currentId = viewModel.selectedSession?.id ?? session.id
            viewModel.updateRuntimeState(for: currentId, state: info.state, cpu: info.cpu, memory: info.memory, pid: info.pid)
          },
          onShellStart: { shellPid in
            // Use current session ID (may have changed after sync)
            let currentId = viewModel.selectedSession?.id ?? session.id
            viewModel.setShellPid(shellPid, for: currentId)
          },
          onSessionActivated: { sessionId in
            viewModel.appModel.markSessionActivated(sessionId)
            viewModel.appModel.trackSessionForHooks(sessionId)
          },
          onRegisterForInput: { terminal, sessionId in
            viewModel.appModel.terminalInput.register(terminal, for: sessionId)
          },
          onUnregisterForInput: { sessionId in
            viewModel.appModel.terminalInput.unregister(sessionId: sessionId)
          }
        )
        .id(session.terminalId)
        .opacity(viewModel.isTerminalVisible ? 1 : 0)
        .allowsHitTesting(viewModel.isTerminalVisible)
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
