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

import Dependencies
import Foundation

/// Represents a hook event from Claude Code
struct HookEvent: Codable {
  let sessionId: String
  let event: String
  let state: String
  let cwd: String?
  let tool: String?
  let message: String?
  let toolInput: ToolInput?
  let timestamp: String

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case event, state, cwd, tool, message, timestamp
    case toolInput = "tool_input"
  }

  /// Parse timestamp to Date
  var date: Date? {
    ISO8601DateFormatter().date(from: timestamp)
  }
}

/// Tool input details (for permission prompts)
struct ToolInput: Codable {
  let command: String?
  let filePath: String?
  let content: String?

  enum CodingKeys: String, CodingKey {
    case command, content
    case filePath = "file_path"
  }
}

/// State derived from hook events
enum HookState: String, Codable {
  case processing  // User submitted prompt, Claude starting to process
  case thinking    // Claude is using tools, actively working
  case waiting     // Claude finished, waiting for user input
  case waitingPermission  // Claude is waiting for user permission (tool approval)
  case started     // Session just started
  case ended       // Session ended
  case unknown
}

/// Service that monitors hook events and updates session states
@MainActor
@Observable
final class HookEventService {

  /// Events file path — resolved from DependencyValues at init time.
  /// Override via withDependencies { $0.hookEventsFilePath = … } before creating the instance.
  private let eventsFilePath: URL

  /// File handle for reading
  private var fileHandle: FileHandle?

  /// Dispatch source for file monitoring
  private var dispatchSource: DispatchSourceFileSystemObject?

  /// Last file offset we read from
  private var lastReadOffset: UInt64 = 0

  /// Latest state per session
  private(set) var sessionStates: [String: HookState] = [:]

  /// Latest tool being used per session
  private(set) var sessionTools: [String: String] = [:]

  /// Latest event timestamp per session
  private(set) var sessionTimestamps: [String: Date] = [:]

  /// Latest permission message per session (for permission prompts)
  private(set) var sessionMessages: [String: String] = [:]

  /// Callback when a session state changes (sessionId, state, tool, message, eventTime)
  var onStateChange: ((String, HookState, String?, String?, Date?) -> Void)?

  init() {
    @Dependency(\.hookEventsFilePath) var filePath
    self.eventsFilePath = filePath
  }

  /// Start monitoring hook events
  func startMonitoring() {
    // Ensure file exists
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: eventsFilePath.path) {
      // Create empty file
      try? fileManager.createDirectory(
        at: eventsFilePath.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      fileManager.createFile(atPath: eventsFilePath.path, contents: nil)
    }

    // Open file for reading
    guard let handle = FileHandle(forReadingAtPath: eventsFilePath.path) else {
      print("HookEventService: Failed to open events file")
      return
    }
    fileHandle = handle

    // Seek to end to only read new events
    handle.seekToEndOfFile()
    lastReadOffset = handle.offsetInFile

    // Set up dispatch source to monitor file changes
    let fd = handle.fileDescriptor
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.extend, .write],
      queue: .main
    )

    source.setEventHandler { [weak self] in
      self?.readNewEvents()
    }

    source.setCancelHandler { [weak self] in
      self?.fileHandle?.closeFile()
      self?.fileHandle = nil
    }

    dispatchSource = source
    source.resume()

    // Also read any existing recent events (last 50 lines)
    readRecentEvents()

    print("HookEventService: Started monitoring \(eventsFilePath.path)")
  }

  /// Stop monitoring
  func stopMonitoring() {
    dispatchSource?.cancel()
    dispatchSource = nil
    fileHandle?.closeFile()
    fileHandle = nil
  }

  /// Read recent events from the file (on startup)
  /// Only processes events from the last few seconds to avoid stale state
  private func readRecentEvents() {
    guard let data = try? Data(contentsOf: eventsFilePath),
          let content = String(data: data, encoding: .utf8) else {
      return
    }

    let lines = content.components(separatedBy: .newlines)
      .filter { !$0.isEmpty }
      .suffix(20)  // Last 20 events

    let cutoffTime = Date().addingTimeInterval(-10)  // Only events from last 10 seconds
    let formatter = ISO8601DateFormatter()

    for line in lines {
      // Parse to check timestamp before processing
      guard let data = line.data(using: .utf8),
            let event = try? JSONDecoder().decode(HookEvent.self, from: data),
            let eventDate = formatter.date(from: event.timestamp),
            eventDate > cutoffTime else {
        continue
      }
      processEventLine(line)
    }
  }

  /// Read new events appended to the file
  private func readNewEvents() {
    guard let handle = fileHandle else { return }

    // Read from last position
    handle.seek(toFileOffset: lastReadOffset)
    let data = handle.readDataToEndOfFile()
    lastReadOffset = handle.offsetInFile

    guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
      return
    }

    let lines = content.components(separatedBy: .newlines)
      .filter { !$0.isEmpty }

    for line in lines {
      processEventLine(line)
    }
  }

  /// Process a single event line
  private func processEventLine(_ line: String) {
    guard let data = line.data(using: .utf8),
          let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
      return
    }

    let state = HookState(rawValue: event.state) ?? .unknown
    let sessionId = event.sessionId

    // Update state
    sessionStates[sessionId] = state

    // Update tool if present
    if let tool = event.tool {
      sessionTools[sessionId] = tool
    } else if state == .waiting || state == .waitingPermission {
      // Clear tool when waiting
      sessionTools.removeValue(forKey: sessionId)
    }

    // Update message for permission prompts
    var permissionMessage: String? = nil
    if state == .waitingPermission {
      // Build a descriptive message from available data
      if let message = event.message, !message.isEmpty {
        permissionMessage = message
        sessionMessages[sessionId] = message
      } else if let toolInput = event.toolInput {
        // Build message from tool input
        if let command = toolInput.command {
          permissionMessage = "Run command: \(command)"
        } else if let filePath = toolInput.filePath {
          permissionMessage = "Edit file: \(filePath)"
        }
        if let msg = permissionMessage {
          sessionMessages[sessionId] = msg
        }
      }
    } else {
      // Clear message when not waiting for permission
      sessionMessages.removeValue(forKey: sessionId)
    }

    // Update timestamp
    let eventDate = event.date
    if let date = eventDate {
      sessionTimestamps[sessionId] = date
    }

    // Notify callback with event timestamp and message
    onStateChange?(sessionId, state, event.tool, permissionMessage, eventDate)
  }

  /// Get the current hook state for a session
  func state(for sessionId: String) -> HookState? {
    sessionStates[sessionId]
  }

  /// Get the current tool being used for a session
  func currentTool(for sessionId: String) -> String? {
    sessionTools[sessionId]
  }

  /// Check if we have recent activity for a session (within last 5 minutes)
  func hasRecentActivity(for sessionId: String) -> Bool {
    guard let timestamp = sessionTimestamps[sessionId] else { return false }
    return Date().timeIntervalSince(timestamp) < 300  // 5 minutes
  }

  /// Clear all cached states (used when hooks are uninstalled)
  func clearAllStates() {
    sessionStates.removeAll()
    sessionTools.removeAll()
    sessionTimestamps.removeAll()
    sessionMessages.removeAll()
  }

  /// Clear state for a specific session
  func clearState(for sessionId: String) {
    sessionStates.removeValue(forKey: sessionId)
    sessionTools.removeValue(forKey: sessionId)
    sessionTimestamps.removeValue(forKey: sessionId)
    sessionMessages.removeValue(forKey: sessionId)
  }
}
