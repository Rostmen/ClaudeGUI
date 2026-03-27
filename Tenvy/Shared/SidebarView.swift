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

struct SidebarView: View {
  var sessionManager: any SessionDiscovery
  @Binding var selectedSession: ClaudeSession?
  @Binding var selectedDiffFile: GitChangedFile?
  var onCreateNewSession: ((ClaudeSession) -> Void)?
  var onSelectSession: ((ClaudeSession) -> Void)?
  var runtimeState: SessionRuntimeRegistry
  var activeSessionIds: Set<String>
  var activatedSessions: [String: ClaudeSession]

  private let settings = AppSettings.shared
  @State private var selectedTab: SidebarTab = .sessions

  init(
    sessionManager: any SessionDiscovery,
    selectedSession: Binding<ClaudeSession?>,
    selectedDiffFile: Binding<GitChangedFile?>,
    onCreateNewSession: ((ClaudeSession) -> Void)? = nil,
    onSelectSession: ((ClaudeSession) -> Void)? = nil,
    runtimeState: SessionRuntimeRegistry,
    activeSessionIds: Set<String> = [],
    activatedSessions: [String: ClaudeSession] = [:]
  ) {
    self.sessionManager = sessionManager
    self._selectedSession = selectedSession
    self._selectedDiffFile = selectedDiffFile
    self.onCreateNewSession = onCreateNewSession
    self.onSelectSession = onSelectSession
    self.runtimeState = runtimeState
    self.activeSessionIds = activeSessionIds
    self.activatedSessions = activatedSessions
  }

  /// Tabs to show based on settings
  private var availableTabs: [SidebarTab] {
    var tabs: [SidebarTab] = [.sessions]
    if settings.gitChangesEnabled {
      tabs.append(.changes)
    }
    return tabs
  }

  var body: some View {
    VStack(spacing: 0) {
      // Tab bar at top (only if more than one tab)
      if availableTabs.count > 1 {
        SidebarTabBar(selectedTab: $selectedTab, availableTabs: availableTabs)
      }

      // Keep all views alive to preserve state, control visibility with ZStack
      ZStack {
        // Sessions tab
        SessionListView(
          sessionManager: sessionManager,
          selectedSession: $selectedSession,
          onCreateNewSession: onCreateNewSession,
          onSelectSession: onSelectSession,
          runtimeState: runtimeState,
          activeSessionIds: activeSessionIds,
          activatedSessions: activatedSessions
        )
        .opacity(selectedTab == .sessions ? 1 : 0)
        .allowsHitTesting(selectedTab == .sessions)

        // Changes tab (only if enabled)
        if settings.gitChangesEnabled {
          Group {
            if let session = selectedSession {
              GitChangesView(rootPath: session.workingDirectory, selectedFile: $selectedDiffFile)
            } else {
              NoSessionSelectedView()
            }
          }
          .opacity(selectedTab == .changes ? 1 : 0)
          .allowsHitTesting(selectedTab == .changes)
        }
      }
    }
    .onChange(of: selectedTab) { _, newTab in
      if newTab == .sessions {
        selectedDiffFile = nil
      }
    }
    .onChange(of: availableTabs) { _, newTabs in
      // If current tab is no longer available, switch to sessions
      if !newTabs.contains(selectedTab) {
        selectedTab = .sessions
      }
    }
  }
}

#Preview {
  SidebarView(
    sessionManager: SessionManager(),
    selectedSession: .constant(nil),
    selectedDiffFile: .constant(nil),
    runtimeState: SessionRuntimeRegistry()
  )
  .frame(width: 280, height: 500)
  .background(Color.black.opacity(0.8))
}
