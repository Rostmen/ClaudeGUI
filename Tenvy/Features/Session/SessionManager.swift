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

import Foundation

@MainActor
@Observable
class SessionManager {
  var sessions: [ClaudeSession] = []
  var isLoading = false
  var error: Error?

  private let claudeProjectsPath: URL
  private let fileManager = FileManager.default
  private var directoryMonitor: DirectoryMonitor?

  /// Persistent session store — sessions discovered from disk are upserted here.
  var sessionStore: SessionStore?

  init() {
    let homeDirectory = fileManager.homeDirectoryForCurrentUser
    claudeProjectsPath = homeDirectory.appendingPathComponent(".claude/projects")
    startWatchingForChanges()
  }

  /// Add a new session to the list (for newly created sessions)
  func addSession(_ session: ClaudeSession) {
    // Insert at the beginning since it's the most recent
    sessions.insert(session, at: 0)
  }

  /// Start watching the projects directory for changes
  private func startWatchingForChanges() {
    directoryMonitor = DirectoryMonitor(url: claudeProjectsPath) { [weak self] in
      Task { @MainActor in
        await self?.loadSessions()
      }
    }
    directoryMonitor?.start()
  }

  func loadSessions() async {
    isLoading = true
    error = nil

    do {
      sessions = try await scanForSessions()
    } catch {
      self.error = error
      sessions = []
    }

    isLoading = false
  }

  private func scanForSessions() async throws -> [ClaudeSession] {
    guard fileManager.fileExists(atPath: claudeProjectsPath.path) else {
      return []
    }

    let projectDirs = try fileManager.contentsOfDirectory(
      at: claudeProjectsPath,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    var allSessions: [ClaudeSession] = []

    for projectDir in projectDirs {
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: projectDir.path, isDirectory: &isDirectory),
         isDirectory.boolValue else {
        continue
      }

      let projectPath = decodeProjectPath(projectDir.lastPathComponent)
      let sessionsInProject = try await loadSessionsFromProject(
        projectDir: projectDir,
        projectPath: projectPath
      )
      allSessions.append(contentsOf: sessionsInProject)
    }

    return allSessions.sorted { $0.lastModified > $1.lastModified }
  }

  private func loadSessionsFromProject(projectDir: URL, projectPath: String) async throws -> [ClaudeSession] {
    let contents = try fileManager.contentsOfDirectory(
      at: projectDir,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: []
    )

    let jsonlFiles = contents.filter { $0.pathExtension == "jsonl" }
    var sessions: [ClaudeSession] = []

    for jsonlFile in jsonlFiles {
      do {
        if let session = try await parseSessionFile(jsonlFile, projectPath: projectPath) {
          sessions.append(session)
        }
      } catch {
        // Skip files that can't be parsed
        continue
      }
    }

    return sessions
  }

  private func parseSessionFile(_ fileURL: URL, projectPath: String) async throws -> ClaudeSession? {
    let sessionId = fileURL.deletingPathExtension().lastPathComponent

    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
    let lastModified = attributes[.modificationDate] as? Date ?? Date.distantPast

    var title = "Untitled Session"
    var workingDirectory = projectPath

    // Read file contents and scan for session content
    let fullData = try Data(contentsOf: fileURL)
    let lines = fullData.split(separator: UInt8(ascii: "\n"), maxSplits: 100)

    var foundSummary = false
    var hasConversationContent = false

    // Types that indicate this is a real session with conversation content
    let conversationTypes: Set<String> = ["summary", "user", "assistant", "system"]

    for line in lines {
      let lineData = Data(line)

      // Check the type of this line
      if let typeInfo = try? JSONDecoder().decode(MessageType.self, from: lineData) {
        if conversationTypes.contains(typeInfo.type) {
          hasConversationContent = true
        }

        // Try to find a summary line for the title
        if !foundSummary && typeInfo.type == "summary",
           let summary = try? JSONDecoder().decode(SessionSummary.self, from: lineData),
           let summaryText = summary.summary {
          foundSummary = true
          title = summaryText
        }
      }

      // Try to find cwd from messages
      if workingDirectory == projectPath,
         let message = try? JSONDecoder().decode(SessionMessage.self, from: lineData),
         let cwd = message.cwd {
        workingDirectory = cwd
      }

      // Stop early if we found everything we need
      if foundSummary && hasConversationContent && workingDirectory != projectPath {
        break
      }
    }

    // Only include files that have actual conversation content
    // Skip files that only contain file-history-snapshot entries
    guard hasConversationContent else {
      return nil
    }

    // Upsert into persistent DB so @Query views see discovered sessions
    try? sessionStore?.upsertFromSessionFile(
      claudeSessionId: sessionId,
      title: title,
      filePath: fileURL.path,
      lastModified: lastModified,
      workingDirectory: workingDirectory,
      projectPath: projectPath
    )

    return ClaudeSession(
      id: sessionId,
      title: title,
      projectPath: projectPath,
      workingDirectory: workingDirectory,
      lastModified: lastModified,
      filePath: fileURL
    )
  }

  /// Minimal struct to just extract the type field from JSON lines
  private struct MessageType: Decodable {
    let type: String
  }

  private func decodeProjectPath(_ encodedPath: String) -> String {
    // Fast path: naive decode works for paths with no hyphens in component names.
    let naive = "/" + encodedPath
      .replacingOccurrences(of: "-", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if fileManager.fileExists(atPath: naive) { return naive }

    // Slow path: probe all interpretations treating each '-' as either '/' or a
    // literal hyphen in a component name, returning the deepest real path found.
    return bestMatchingPath(for: encodedPath) ?? naive
  }

  /// Try all 2^N interpretations of hyphens in the encoded string, returning the
  /// deepest real filesystem path found. N is capped at 20 to avoid combinatorial
  /// explosion on unusually long paths.
  private func bestMatchingPath(for encoded: String) -> String? {
    let parts = encoded.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    guard parts.count <= 20 else { return nil }

    var best: String?

    func probe(index: Int, current: String) {
      let fullPath = "/" + current.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      if fileManager.fileExists(atPath: fullPath) {
        if best == nil || fullPath.count > best!.count {
          best = fullPath
        }
      }
      guard index < parts.count else { return }
      // Option 1: this '-' is a path separator
      probe(index: index + 1, current: current + "/" + parts[index])
      // Option 2: this '-' is a literal hyphen in a component name
      if !current.isEmpty {
        probe(index: index + 1, current: current + "-" + parts[index])
      }
    }

    if let first = parts.first {
      probe(index: 1, current: first)
    }
    return best
  }

  func deleteSession(_ session: ClaudeSession) throws {
    // Remove from persistent DB
    try? sessionStore?.deleteSession(terminalId: session.terminalId)

    guard let filePath = session.filePath else {
      // New session without a file - just remove from list
      sessions.removeAll { $0.id == session.id }
      return
    }

    // Delete the jsonl file
    try fileManager.removeItem(at: filePath)

    // Delete the session folder if it exists
    let sessionFolder = filePath.deletingPathExtension()
    if fileManager.fileExists(atPath: sessionFolder.path) {
      try fileManager.removeItem(at: sessionFolder)
    }

    // Update the list
    sessions.removeAll { $0.id == session.id }
  }

  func renameSession(_ session: ClaudeSession, to newTitle: String) throws {
    guard let filePath = session.filePath,
       let data = fileManager.contents(atPath: filePath.path),
       let content = String(data: data, encoding: .utf8) else {
      throw SessionError.cannotReadFile
    }

    var lines = content.components(separatedBy: "\n")
    guard !lines.isEmpty else {
      throw SessionError.invalidFormat
    }

    // Parse and update the first line
    guard let firstLineData = lines[0].data(using: .utf8),
       let summary = try? JSONDecoder().decode(SessionSummary.self, from: firstLineData) else {
      throw SessionError.invalidFormat
    }

    // Create updated summary
    let updatedSummary = """
    {"type":"summary","summary":"\(newTitle.replacingOccurrences(of: "\"", with: "\\\""))","leafUuid":"\(summary.leafUuid ?? UUID().uuidString)"}
    """
    lines[0] = updatedSummary

    let updatedContent = lines.joined(separator: "\n")
    try updatedContent.write(to: filePath, atomically: true, encoding: .utf8)

    // Update in memory
    if let index = sessions.firstIndex(where: { $0.id == session.id }) {
      sessions[index] = ClaudeSession(
        id: session.id,
        title: newTitle,
        projectPath: session.projectPath,
        workingDirectory: session.workingDirectory,
        lastModified: session.lastModified,
        filePath: session.filePath
      )
    }

    // Update in persistent DB
    try? sessionStore?.updateTitle(terminalId: session.terminalId, title: newTitle)
  }
}

enum SessionError: LocalizedError {
  case cannotReadFile
  case invalidFormat

  var errorDescription: String? {
    switch self {
    case .cannotReadFile:
      return "Cannot read session file"
    case .invalidFormat:
      return "Invalid session file format"
    }
  }
}

extension FileHandle {
  func readLine() throws -> Data? {
    var lineData = Data()
    while true {
      guard let byte = try read(upToCount: 1), !byte.isEmpty else {
        return lineData.isEmpty ? nil : lineData
      }
      if byte[0] == UInt8(ascii: "\n") {
        return lineData
      }
      lineData.append(byte)
    }
  }
}

/// Watches a directory tree for changes using FSEvents (kernel-level, efficient)
class DirectoryMonitor {
  private let url: URL
  private let onChange: () -> Void
  private var stream: FSEventStreamRef?
  private var debounceWorkItem: DispatchWorkItem?

  init(url: URL, onChange: @escaping () -> Void) {
    self.url = url
    self.onChange = onChange
  }

  deinit {
    stop()
  }

  func start() {
    guard stream == nil else { return }

    // Use retained reference to prevent deallocation while stream is active
    let retainedSelf = Unmanaged.passRetained(self)

    var context = FSEventStreamContext()
    context.info = retainedSelf.toOpaque()
    // Release callback to balance the retain when stream is invalidated
    context.release = { info in
      guard let info = info else { return }
      Unmanaged<DirectoryMonitor>.fromOpaque(info).release()
    }
    // Retain callback (not needed since we already retained, but required for symmetry)
    context.retain = { info in
      guard let info = info else { return nil }
      return UnsafeRawPointer(Unmanaged<DirectoryMonitor>.fromOpaque(info).retain().toOpaque())
    }

    let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
      guard let info = info else { return }
      let monitor = Unmanaged<DirectoryMonitor>.fromOpaque(info).takeUnretainedValue()
      monitor.handleChange()
    }

    let paths = [url.path as CFString] as CFArray
    stream = FSEventStreamCreate(
      nil,
      callback,
      &context,
      paths,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      0.5, // Latency in seconds (batches events)
      UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
    )

    guard let stream = stream else {
      print("DirectoryMonitor: Failed to create FSEventStream for \(url.path)")
      // Release since we won't be using the stream
      retainedSelf.release()
      return
    }

    FSEventStreamSetDispatchQueue(stream, .main)
    FSEventStreamStart(stream)
  }

  func stop() {
    debounceWorkItem?.cancel()
    debounceWorkItem = nil
    guard let stream = stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream) // This triggers the release callback
    FSEventStreamRelease(stream)
    self.stream = nil
  }

  private func handleChange() {
    // Additional debounce for rapid successive events
    debounceWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.onChange()
    }
    debounceWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
  }
}
