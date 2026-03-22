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

/// Analyzes process tree to find Claude processes
struct ProcessTreeAnalyzer {
  /// Find Claude process that is a descendant of a shell process
  /// - Parameters:
  ///   - shellPID: The shell process ID to search from (may actually be Claude's PID if spawned directly)
  ///   - sessionId: Optional session ID to match in process arguments
  /// - Returns: The Claude process PID, or 0 if not found
  static func findClaudeProcess(shellPID: pid_t, sessionId: String?) -> pid_t {
    let (parentMap, candidates) = getProcessTree(sessionId: sessionId)

    // Check if shellPID itself is a Claude process (happens when claude is spawned directly,
    // e.g., after "claude install" which installs a native binary)
    if candidates.contains(shellPID) {
      return shellPID
    }

    // Find candidate that is descendant of our shell
    for candidatePid in candidates {
      if isDescendant(pid: candidatePid, of: shellPID, parentMap: parentMap) {
        return candidatePid
      }
    }

    return 0
  }

  /// Get the process tree and Claude candidates
  private static func getProcessTree(sessionId: String?) -> (parentMap: [pid_t: pid_t], candidates: [pid_t]) {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", "ps -eo pid,ppid,args"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    guard let output = String(data: data, encoding: .utf8) else {
      return ([:], [])
    }

    return parseProcessOutput(output, sessionId: sessionId)
  }

  /// Parse ps output into parent map and candidate PIDs
  private static func parseProcessOutput(_ output: String, sessionId: String?) -> (parentMap: [pid_t: pid_t], candidates: [pid_t]) {
    var parentMap: [pid_t: pid_t] = [:]
    var candidates: [pid_t] = []

    let lines = output.components(separatedBy: "\n")
    for line in lines {
      let parts = line.trimmingCharacters(in: .whitespaces)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }

      guard parts.count >= 3,
            let pid = Int32(parts[0]),
            let ppid = Int32(parts[1]) else { continue }

      parentMap[pid] = ppid

      // Check if this is a Claude process
      let args = parts[2...].joined(separator: " ")
      if isClaudeProcess(args: args, sessionId: sessionId) {
        candidates.append(pid)
      }
    }

    return (parentMap, candidates)
  }

  /// Check if process arguments indicate a Claude process
  private static func isClaudeProcess(args: String, sessionId: String?) -> Bool {
    // Look for the claude CLI process
    guard args.contains("claude") else {
      return false
    }

    // If we have a session ID, verify it matches
    if let sessionId = sessionId, !sessionId.isEmpty {
      return args.contains(sessionId)
    }

    return true
  }

  /// Check if pid is a descendant of ancestorPID using the parent map
  private static func isDescendant(pid: pid_t, of ancestorPID: pid_t, parentMap: [pid_t: pid_t]) -> Bool {
    var current = pid
    while let parent = parentMap[current] {
      if parent == ancestorPID { return true }
      if parent <= 1 { return false }  // Reached init/launchd
      current = parent
    }
    return false
  }
}
