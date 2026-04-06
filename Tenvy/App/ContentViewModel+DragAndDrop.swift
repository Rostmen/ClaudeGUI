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

import AppKit
import Combine
import Foundation
import GhosttyEmbed
import GRDBQuery
import SwiftUI

// MARK: - Drag & Drop Transfer + File Drop

extension ContentViewModel {

  /// Whether this ViewModel owns a terminal with the given tenvySessionId.
  func ownsTerminal(_ tenvySessionId: String) -> Bool {
    ghosttyHostViews[tenvySessionId] != nil
  }

  /// Whether this ViewModel owns the given session (for cross-window transfer).
  func ownsSession(_ sessionId: String) -> Bool {
    if selectedSession?.id == sessionId { return true }
    if splitTree?.contains(sessionId: sessionId) == true { return true }
    return false
  }

  /// Release a session for transfer to another window.
  /// Extracts the host view (without closing it), deposits on AppModel,
  /// and removes the session from this window's split tree / selection.
  func prepareForTransfer(sessionId: String) {
    let session: ClaudeSession?
    if let s = splitTree?.allSessions.first(where: { $0.id == sessionId }) {
      session = s
    } else if selectedSession?.id == sessionId {
      session = selectedSession
    } else {
      return
    }
    guard let session else { return }

    // Extract host view WITHOUT closing — deposit for the destination to pick up
    if let hostView = ghosttyHostViews.removeValue(forKey: session.tenvySessionId) {
      appModel.depositForTransfer(tenvySessionId: session.tenvySessionId, hostView: hostView)
    }

    // Remove from this window's structure (without deactivating — session stays alive)
    detachSessionFromWindow(sessionId: sessionId)
  }

  /// Receive a transferred session and insert it alongside an existing session.
  /// Called directly (same window) or via AppModel (cross-window).
  func receiveTransferredSession(_ session: ClaudeSession, alongside targetSessionId: String, direction: SplitDirection = .right) {
    if let hostView = appModel.pickupTransfer(tenvySessionId: session.tenvySessionId) {
      ghosttyHostViews[session.tenvySessionId] = hostView
      // Re-subscribe to title updates for plain terminals
      subscribePlainTerminalTitle(tenvySessionId: session.tenvySessionId, surface: hostView.surface)
    }
    appModel.activateSession(session)
    insertSplitPane(session, at: targetSessionId, direction: direction)
  }

  /// Handle a pane header dragged outside any window — open in a new window.
  func handlePaneDragToNewWindow(tenvySessionId: String) {
    // Find the session by tenvySessionId
    guard let session = findSessionByTerminalId(tenvySessionId) else { return }

    // If this session is already alone in its window (no split), dragging outside is a no-op.
    // The session is already in a dedicated window — nothing to detach from.
    if !isInSplitMode && selectedSession?.id == session.id {
      return
    }

    handleDragToNewWindow(sessionId: session.id)
  }

  /// Find a session by tenvySessionId, searching local state and activated sessions.
  func findSessionByTerminalId(_ tenvySessionId: String) -> ClaudeSession? {
    if let tree = splitTree, let s = tree.allSessions.first(where: { $0.tenvySessionId == tenvySessionId }) {
      return s
    }
    if selectedSession?.tenvySessionId == tenvySessionId { return selectedSession }
    return appModel.activatedSessions.values.first(where: { $0.tenvySessionId == tenvySessionId })
  }

  /// Handle a session dragged to the "New Window" drop zone.
  /// Transfers the host view to a new window without restarting the process.
  ///
  /// Mirrors Ghostty's `ghosttySurfaceDragEndedNoTarget` pattern:
  /// 1. Extract host view from source cache
  /// 2. Create new window with pre-configured ViewModel (host view already loaded)
  /// 3. THEN remove session from source split tree
  /// This ensures the host view is owned by the new ViewModel before SwiftUI
  /// destroys the old wrapper in the source window's re-render.
  func handleDragToNewWindow(sessionId: String) {
    guard let session = appModel.activatedSessions[sessionId] else { return }

    // 1. Extract host view from source cache (without modifying split tree yet)
    let hostView = ghosttyHostViews.removeValue(forKey: session.tenvySessionId)

    // 2. Create new ViewModel pre-loaded with session and host view
    let newVM = ContentViewModel(appModel: appModel)
    newVM.preloadForTransfer(session: session, hostView: hostView, isPlainTerminal: isPlainTerminal(session.tenvySessionId))

    // 3. Create new window using AppKit (like Ghostty's TerminalController.newWindow)
    let rootView = ContentView(viewModel: newVM)
      .environment(appModel)
      .databaseContext(.readOnly { AppDatabase.shared.databaseReader })
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .visible
    window.isOpaque = false
    window.backgroundColor = .clear
    window.title = session.title

    // Size to match source window
    if let sourceFrame = currentWindow?.frame {
      window.setFrame(sourceFrame, display: false)
    } else {
      window.setContentSize(NSSize(width: 800, height: 600))
    }

    window.makeKeyAndOrderFront(nil)

    // 4. NOW remove from source split tree (safe — host view is in new ViewModel)
    detachSessionFromWindow(sessionId: sessionId)
  }

  /// Pre-load a session and host view for a cross-window transfer.
  /// Called on the destination ViewModel before the window is shown.
  func preloadForTransfer(session: ClaudeSession, hostView: GhosttyHostView?, isPlainTerminal: Bool) {
    selectedSession = session
    appModel.activateSession(session)
    if let hostView {
      ghosttyHostViews[session.tenvySessionId] = hostView
    }
    if isPlainTerminal {
      plainTerminalIds.insert(session.tenvySessionId)
      subscribePlainTerminalTitle(tenvySessionId: session.tenvySessionId, surface: hostView?.surface)
    }
  }

  /// Removes a session from the split tree and re-binds the window.
  /// Shared by `prepareForTransfer`, `handleDragToNewWindow`, and legacy `removePaneFromSource`.
  func detachSessionFromWindow(sessionId: String) {
    if isInSplitMode && splitTree?.contains(sessionId: sessionId) == true {
      let wasSelected = selectedSession?.id == sessionId
      let wasPrimary = currentWindow?.sessionId == sessionId

      if let newTree = splitTree?.removing(sessionId: sessionId) {
        let remaining = newTree.allSessions
        if remaining.count <= 1 {
          splitTree = nil
          if wasSelected { selectedSession = remaining.first ?? primarySession }
        } else {
          splitTree = newTree
          if wasSelected { selectedSession = primarySession ?? remaining.first }
        }
      } else {
        splitTree = nil
        if wasSelected { selectedSession = nil }
      }

      // Re-register window if the primary was removed
      if wasPrimary {
        bindWindowToSession(splitTree?.allSessions.first ?? selectedSession)
      }
    } else {
      // Single session — clear this window
      selectedSession = nil
      bindWindowToSession(nil)
    }

    // Close the now-empty window (unless it's the last visible one)
    if selectedSession == nil && !isInSplitMode, let window = currentWindow {
      let visibleWindows = NSApp.windows.filter { $0.isVisible && $0 != window }
      if !visibleWindows.isEmpty {
        window.close()
      }
    }
  }

  /// Move a pane from one position to another (same-window rearrange or cross-window transfer).
  func movePaneToSplit(sourceTerminalId: String, destinationTerminalId: String, zone: PaneDropZone) {
    guard sourceTerminalId != destinationTerminalId else { return }

    let direction = zone.splitDirection

    // Find destination session (must be in this window)
    let localSessions: [ClaudeSession]
    if let tree = splitTree {
      localSessions = tree.allSessions
    } else if let session = selectedSession {
      localSessions = [session]
    } else {
      return
    }
    guard let destSession = localSessions.first(where: { $0.tenvySessionId == destinationTerminalId }) else { return }

    // Check if source is in this window
    if let sourceSession = localSessions.first(where: { $0.tenvySessionId == sourceTerminalId }) {
      // Same-window move within split tree
      guard let tree = splitTree else { return }
      guard let newTree = tree.moving(sessionId: sourceSession.id, toDestination: destSession.id, direction: direction) else {
        return
      }
      let remaining = newTree.allSessions
      if remaining.count <= 1 {
        splitTree = nil
        selectedSession = remaining.first
        bindWindowToSession(remaining.first)
      } else {
        splitTree = newTree
        selectedSession = sourceSession
      }
    } else {
      // Cross-window: source is in another window
      guard let sourceSession = appModel.activatedSessions.values.first(where: { $0.tenvySessionId == sourceTerminalId }) else { return }

      // Release from source window (deposits host view on AppModel)
      appModel.releaseSessionForTransfer(sessionId: sourceSession.id)

      // Receive into this window alongside the destination
      receiveTransferredSession(sourceSession, alongside: destSession.id, direction: direction)
    }
  }

  // MARK: - File Drop

  /// Focuses the pane with the given terminal ID — used when files are dropped on a non-focused pane.
  func focusPane(tenvySessionId: String) {
    guard let session = findSessionByTerminalId(tenvySessionId),
          selectedSession?.tenvySessionId != tenvySessionId else { return }
    selectedSession = session
    ghosttyHostView(for: tenvySessionId)?.makeFocused()
  }

  /// Handles file drop in single-pane mode (SwiftUI fallback).
  /// GhosttyHostView's AppKit drag handler doesn't fire in single-pane because
  /// SwiftUI's hosting layer intercepts drags before they reach child NSViews.
  func handleSinglePaneFileDrop(providers: [NSItemProvider], tenvySessionId: String) -> Bool {
    guard let hostView = ghosttyHostView(for: tenvySessionId) else { return false }

    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()

    for provider in providers {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        defer { group.leave() }
        guard let url else { return }
        lock.lock()
        urls.append(url)
        lock.unlock()
      }
    }

    group.notify(queue: .main) {
      guard !urls.isEmpty else { return }
      let text = urls
        .map { GhosttyHostView.shellEscape($0.path) }
        .joined(separator: " ")
      hostView.surface?.sendText(text)
    }
    return true
  }

  /// Handler for split-pane terminals that also auto-closes when the claude process ends.
  func handleSplitTerminalAction(_ action: TerminalAction, for session: ClaudeSession) {
    handleTerminalAction(action, for: session)
    if case .stateChanged(let info) = action,
       primarySession?.id != session.id && info.state == .inactive {
      closeSplitPane(id: session.id)
    }
  }
}
