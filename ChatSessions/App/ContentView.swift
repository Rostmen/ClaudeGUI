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
  @State private var viewModel = ContentViewModel()
  @State private var hookInstallationService = HookInstallationService.shared

  // UI-only state
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var terminalFrame: CGRect = .zero
  @State private var currentWindow: NSWindow?
  @State private var showHookPrompt: Bool = false

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

      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarView(
          sessionManager: viewModel.sessionManager,
          selectedSession: Binding(
            get: { viewModel.selectedSession },
            set: { _ in } // Read-only, use viewModel.selectSession instead
          ),
          selectedFilePath: $viewModel.selectedFilePath,
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
      .navigationTitle("")

      // Hook installation prompt overlay
      if showHookPrompt {
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
    }
    .onChange(of: viewModel.sessionManager.sessions) { _, _ in
      // When sessions reload, sync new sessions with Claude-created ones
      viewModel.syncNewSessionWithDiscoveredSession()
    }
    .onChange(of: hookInstallationService.shouldShowPrompt) { _, shouldShow in
      withAnimation(.easeInOut(duration: 0.3)) {
        showHookPrompt = shouldShow
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .openSessionFromNotification)) { notification in
      if let session = notification.object as? ClaudeSession {
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
          }
        )
        .id(session.terminalId)
        .opacity(viewModel.isTerminalVisible ? 1 : 0)
        .allowsHitTesting(viewModel.isTerminalVisible)
        .background(terminalFrameReader(visible: viewModel.isTerminalVisible))
        .padding(16)
      }

      // File Editor (shown when file is selected)
      if let filePath = viewModel.selectedFilePath {
        FileEditorView(filePath: filePath)
          .padding(16)
          .background(terminalFrameReader(visible: true))
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
  ContentView()
}
