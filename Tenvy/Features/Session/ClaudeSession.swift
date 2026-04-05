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

enum SessionState {
  case inactive      // Gray - not open
  case thinking      // Yellow - Claude is processing
  case waitingForInput  // Green - waiting for user input
}

struct ClaudeSession: Identifiable, Hashable {
  static func == (lhs: ClaudeSession, rhs: ClaudeSession) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }

  let id: String
  let title: String
  let projectPath: String
  let workingDirectory: String
  let lastModified: Date
  let filePath: URL?
  var isNewSession: Bool = false

  /// Stable Tenvy session identifier — persists through session sync.
  /// Prevents SwiftUI from recreating the terminal when Claude session ID changes.
  let tenvySessionId: String

  init(
    id: String,
    title: String,
    projectPath: String,
    workingDirectory: String,
    lastModified: Date,
    filePath: URL?,
    isNewSession: Bool = false,
    tenvySessionId: String? = nil
  ) {
    self.id = id
    self.title = title
    self.projectPath = projectPath
    self.workingDirectory = workingDirectory
    self.lastModified = lastModified
    self.filePath = filePath
    self.isNewSession = isNewSession
    self.tenvySessionId = tenvySessionId ?? id
  }

  var displayPath: String {
    let components = workingDirectory.split(separator: "/")
    if components.count > 3 {
      return "~/\(components.suffix(2).joined(separator: "/"))"
    }
    return workingDirectory.replacingOccurrences(of: NSHomeDirectory(), with: "~")
  }
}

struct SessionSummary: Decodable {
  let type: String
  let summary: String?
  let leafUuid: String?
}

struct SessionMessage: Decodable {
  let sessionId: String?
  let cwd: String?
  let timestamp: String?
}
