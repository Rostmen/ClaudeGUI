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

enum GitFileStatus: String {
  case modified = "M"
  case added = "A"
  case deleted = "D"
  case renamed = "R"
  case untracked = "?"
  case staged = "S"
}

class GitStatusService {
  private var cachedStatus: [String: GitFileStatus] = [:]
  private var repoRoot: String?

  /// Check if a path is inside a git repository
  func isGitRepository(at path: String) -> Bool {
    let gitPath = (path as NSString).appendingPathComponent(".git")
    return FileManager.default.fileExists(atPath: gitPath)
  }

  /// Find the git repository root for a given path
  func findGitRoot(from path: String) -> String? {
    var currentPath = path
    while currentPath != "/" {
      if isGitRepository(at: currentPath) {
        return currentPath
      }
      currentPath = (currentPath as NSString).deletingLastPathComponent
    }
    return nil
  }

  /// Get git status for all files in a repository
  func getStatus(for rootPath: String) -> [String: GitFileStatus] {
    guard let gitRoot = findGitRoot(from: rootPath) else {
      return [:]
    }

    repoRoot = gitRoot
    cachedStatus = [:]

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["status", "--porcelain", "-uall"]
    process.currentDirectoryURL = URL(fileURLWithPath: gitRoot)

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        parseGitStatus(output, gitRoot: gitRoot)
      }
    } catch {
      // Git command failed, return empty
    }

    return cachedStatus
  }

  private func parseGitStatus(_ output: String, gitRoot: String) {
    let lines = output.components(separatedBy: "\n")

    for line in lines where !line.isEmpty {
      guard line.count >= 3 else { continue }

      let indexStatus = line[line.startIndex]
      let workTreeStatus = line[line.index(line.startIndex, offsetBy: 1)]
      let filePath = String(line.dropFirst(3))

      let fullPath = (gitRoot as NSString).appendingPathComponent(filePath)

      // Determine the status to show
      let status: GitFileStatus?
      if indexStatus == "?" || workTreeStatus == "?" {
        status = .untracked
      } else if indexStatus == "A" || workTreeStatus == "A" {
        status = .added
      } else if indexStatus == "D" || workTreeStatus == "D" {
        status = .deleted
      } else if indexStatus == "R" || workTreeStatus == "R" {
        status = .renamed
      } else if indexStatus == "M" || workTreeStatus == "M" {
        status = .modified
      } else if indexStatus != " " {
        status = .staged
      } else {
        status = nil
      }

      if let status = status {
        cachedStatus[fullPath] = status

        // Also mark parent directories as modified
        var parentPath = (fullPath as NSString).deletingLastPathComponent
        while parentPath != gitRoot && parentPath != "/" {
          if cachedStatus[parentPath] == nil {
            cachedStatus[parentPath] = .modified
          }
          parentPath = (parentPath as NSString).deletingLastPathComponent
        }
      }
    }
  }

  /// Get status for a specific file
  func status(for path: String) -> GitFileStatus? {
    return cachedStatus[path]
  }
}
