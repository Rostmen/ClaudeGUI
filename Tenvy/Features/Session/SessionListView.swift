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
import UniformTypeIdentifiers

struct SessionListView: View {
  var sessionManager: any SessionDiscovery
  @Binding var selectedSession: ClaudeSession?
  var onCreateNewSession: ((ClaudeSession) -> Void)?
  var onSelectSession: ((ClaudeSession) -> Void)?
  var runtimeState: SessionRuntimeRegistry
  var activeSessionIds: Set<String>
  var activatedSessions: [String: ClaudeSession]

  /// Local selection state for responsive UI - synced with selectedSession
  @State private var localSelection: ClaudeSession?
  @State private var sessionToRename: ClaudeSession?
  @State private var newSessionTitle = ""
  @State private var showingRenameAlert = false
  @State private var showingDeleteConfirmation = false
  @State private var sessionToDelete: ClaudeSession?
  @State private var expandedSections: Set<String> = []
  @State private var isExporting = false
  @State private var exportError: String?
  @State private var showExportError = false
  @State private var isImporting = false
  @State private var importError: String?
  @State private var showImportError = false

  /// Active sessions shown at the top (includes optimistic new sessions)
  private var activeSessions: [ClaudeSession] {
    // Build list of active sessions, preferring sessionManager's version if available
    var sessions: [ClaudeSession] = []
    let sessionManagerIds = Set(sessionManager.sessions.map { $0.id })

    for sessionId in activeSessionIds {
      if let managerSession = sessionManager.sessions.first(where: { $0.id == sessionId }) {
        // Use session from sessionManager (has file path, updated title, etc.)
        sessions.append(managerSession)
      } else if let activatedSession = activatedSessions[sessionId] {
        // Optimistic session not yet in sessionManager (new session)
        sessions.append(activatedSession)
      }
    }

    return sessions.sorted { $0.lastModified > $1.lastModified }
  }

  /// Group non-active sessions by their working directory
  private var groupedSessions: [SessionGroupingService.SessionGroup] {
    let nonActiveSessions = sessionManager.sessions.filter { !activeSessionIds.contains($0.id) }
    return SessionGroupingService.groupByWorkingDirectory(nonActiveSessions)
  }

  private func isExpanded(_ folder: String) -> Binding<Bool> {
    Binding(
      get: { expandedSections.contains(folder) },
      set: { isExpanded in
        if isExpanded {
          expandedSections.insert(folder)
        } else {
          expandedSections.remove(folder)
        }
      }
    )
  }

  /// Context menu for session rows - extracted to simplify type checking
  @ViewBuilder
  private func sessionContextMenu(for session: ClaudeSession) -> some View {
    Button("Rename...") {
      sessionToRename = session
      newSessionTitle = session.title
      showingRenameAlert = true
    }

    Button("Export...") {
      exportSession(session)
    }
    .disabled(session.filePath == nil)

    Divider()

    Button("Delete", role: .destructive) {
      sessionToDelete = session
      showingDeleteConfirmation = true
    }
  }

  /// Session list content - extracted to simplify type checking
  private var sessionList: some View {
    List(selection: $localSelection) {
      // Active Sessions section at the top
      if !activeSessions.isEmpty {
        Section(isExpanded: isExpanded("__active__")) {
          ForEach(activeSessions) { session in
            SessionRowView(sessionModel: ClaudeSessionModel(session: session, runtime: runtimeState.info(for: session.id)))
              .tag(session)
              .contextMenu { sessionContextMenu(for: session) }
          }
        } header: {
          Label("Active Sessions", systemImage: "bolt.fill")
            .font(.caption)
            .foregroundColor(ClaudeTheme.accent)
        }
      }

      // Folder-grouped sessions (excluding active ones)
      ForEach(groupedSessions, id: \.folder) { group in
        Section(isExpanded: isExpanded(group.folder)) {
          ForEach(group.sessions) { session in
            SessionRowView(sessionModel: ClaudeSessionModel(session: session, runtime: runtimeState.info(for: session.id)))
              .tag(session)
              .contextMenu { sessionContextMenu(for: session) }
          }
        } header: {
          Text(SessionGroupingService.displayPath(group.folder))
            .font(.caption)
            .foregroundColor(ClaudeTheme.textSecondary)
        }
      }
    }
  }

  var body: some View {
    sessionList
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .alert("Rename Session", isPresented: $showingRenameAlert) {
      TextField("Session Title", text: $newSessionTitle)
      Button("Cancel", role: .cancel) {}
      Button("Rename") {
        if let session = sessionToRename {
          renameSession(session)
        }
      }
    }
    .confirmationDialog(
      "Delete Session",
      isPresented: $showingDeleteConfirmation,
      presenting: sessionToDelete
    ) { session in
      Button("Delete \"\(session.title)\"", role: .destructive) {
        deleteSession(session)
      }
      Button("Cancel", role: .cancel) {}
    } message: { session in
      Text("Are you sure you want to delete this session? This action cannot be undone.")
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: createNewSession) {
          Label("New Session", systemImage: "plus")
        }
      }
    }
    .task {
      await sessionManager.loadSessions()
      // Expand all sections by default (including active)
      expandedSections = Set(groupedSessions.map { $0.folder })
      expandedSections.insert("__active__")
    }
    .onChange(of: sessionManager.sessions) { _, _ in
      // Expand new sections when sessions change
      for group in groupedSessions {
        if !expandedSections.contains(group.folder) {
          expandedSections.insert(group.folder)
        }
      }
    }
    .onChange(of: activeSessionIds) { _, _ in
      // Always keep active section expanded
      expandedSections.insert("__active__")
    }
    .onChange(of: localSelection) { oldValue, newValue in
      // User clicked a session in the list
      guard let session = newValue, session.id != oldValue?.id else { return }

      if let onSelectSession = onSelectSession {
        // Let the callback decide what to do (may switch windows or open new tab)
        onSelectSession(session)
        // If selectedSession didn't change to this session, reset localSelection
        // (the session was opened elsewhere, not in this window)
        DispatchQueue.main.async {
          if selectedSession?.id != session.id {
            localSelection = selectedSession
          }
        }
      } else {
        // No callback, just set directly
        selectedSession = session
      }
    }
    .onChange(of: selectedSession) { _, newValue in
      // Sync localSelection when selectedSession changes externally
      if localSelection?.id != newValue?.id {
        localSelection = newValue
      }
    }
    .onAppear {
      // Sync initial selection
      localSelection = selectedSession
    }
    .alert("Export Error", isPresented: $showExportError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(exportError ?? "Failed to export session")
    }
    .alert("Import Error", isPresented: $showImportError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(importError ?? "Failed to import session")
    }
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      handleDrop(providers: providers)
      return true
    }
    .onReceive(NotificationCenter.default.publisher(for: .importSession)) { _ in
      importSession()
    }
  }

  private func deleteSession(_ session: ClaudeSession) {
    do {
      try sessionManager.deleteSession(session)
      if selectedSession?.id == session.id {
        selectedSession = nil
      }
    } catch {
      print("Failed to delete session: \(error)")
    }
  }

  private func renameSession(_ session: ClaudeSession) {
    guard !newSessionTitle.isEmpty else { return }
    do {
      try sessionManager.renameSession(session, to: newSessionTitle)
    } catch {
      print("Failed to rename session: \(error)")
    }
  }

  private func createNewSession() {
    let panel = NSOpenPanel()
    panel.title = "Choose a folder for new Claude session"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true

    if panel.runModal() == .OK, let url = panel.url {
      let newSession = ClaudeSession(
        id: UUID().uuidString,
        title: "New Session",
        projectPath: url.path,
        workingDirectory: url.path,
        lastModified: Date(),
        filePath: nil,
        isNewSession: true
      )
      onCreateNewSession?(newSession)
    }
  }

  private func exportSession(_ session: ClaudeSession) {
    isExporting = true
    Task {
      do {
        _ = try await SessionExportService.shared.exportSession(session)
      } catch {
        exportError = error.localizedDescription
        showExportError = true
      }
      isExporting = false
    }
  }

  func importSession() {
    isImporting = true
    Task {
      do {
        if let url = await SessionExportService.shared.showImportPanel() {
          _ = try await SessionExportService.shared.importSession(from: url, sessionManager: sessionManager)
        }
      } catch {
        importError = error.localizedDescription
        showImportError = true
      }
      isImporting = false
    }
  }

  private func handleDrop(providers: [NSItemProvider]) {
    for provider in providers {
      provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
        guard error == nil,
              let urlData = data as? Data,
              let urlString = String(data: urlData, encoding: .utf8),
              let url = URL(string: urlString) else {
          return
        }

        // Check if it's a valid session archive
        if SessionExportService.shared.isValidSessionArchive(url) {
          Task { @MainActor in
            isImporting = true
            do {
              _ = try await SessionExportService.shared.importSession(from: url, sessionManager: sessionManager)
            } catch {
              importError = error.localizedDescription
              showImportError = true
            }
            isImporting = false
          }
        }
      }
    }
  }
}
