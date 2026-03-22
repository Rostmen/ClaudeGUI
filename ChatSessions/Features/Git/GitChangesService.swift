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

/// Service for loading and building git changes tree
struct GitChangesService {
  /// Result of loading git changes
  struct ChangesResult {
    let items: [GitChangedFile]
    let expandedPaths: Set<String>
  }

  /// Load git changes for a directory, building a tree structure
  static func loadChanges(at path: String) -> ChangesResult {
    guard let gitRoot = findGitRoot(from: path) else {
      return ChangesResult(items: [], expandedPaths: [])
    }

    let changedFiles = getChangedFiles(in: gitRoot)
    guard !changedFiles.isEmpty else {
      return ChangesResult(items: [], expandedPaths: [])
    }

    return buildTree(from: changedFiles, gitRoot: gitRoot)
  }

  // MARK: - Git Root Detection

  /// Find the git root directory starting from a path
  private static func findGitRoot(from path: String) -> String? {
    var currentPath = path
    while currentPath != "/" {
      let gitPath = (currentPath as NSString).appendingPathComponent(".git")
      if FileManager.default.fileExists(atPath: gitPath) {
        return currentPath
      }
      currentPath = (currentPath as NSString).deletingLastPathComponent
    }
    return nil
  }

  // MARK: - Git Status Parsing

  /// Parsed changed file info
  private struct ParsedChange {
    let relativePath: String
    let status: GitFileStatus
    let fullPath: String
  }

  /// Get list of changed files from git status
  private static func getChangedFiles(in gitRoot: String) -> [ParsedChange] {
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
    } catch {
      return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }

    return parseStatusOutput(output, gitRoot: gitRoot)
  }

  /// Parse git status --porcelain output into structured changes
  private static func parseStatusOutput(_ output: String, gitRoot: String) -> [ParsedChange] {
    var changes: [ParsedChange] = []

    for line in output.components(separatedBy: "\n") where !line.isEmpty {
      guard line.count >= 3 else { continue }

      let indexStatus = line[line.startIndex]
      let workTreeStatus = line[line.index(line.startIndex, offsetBy: 1)]
      let filePath = String(line.dropFirst(3))

      let status = parseFileStatus(index: indexStatus, workTree: workTreeStatus)
      let fullPath = (gitRoot as NSString).appendingPathComponent(filePath)

      changes.append(ParsedChange(relativePath: filePath, status: status, fullPath: fullPath))
    }

    return changes
  }

  /// Parse status characters into GitFileStatus
  private static func parseFileStatus(index: Character, workTree: Character) -> GitFileStatus {
    if index == "?" || workTree == "?" {
      return .untracked
    } else if index == "A" || workTree == "A" {
      return .added
    } else if index == "D" || workTree == "D" {
      return .deleted
    } else if index == "R" || workTree == "R" {
      return .renamed
    } else if index == "M" || workTree == "M" {
      return .modified
    }
    return .modified
  }

  // MARK: - Tree Building

  /// Build tree structure from flat list of changes
  private static func buildTree(from changes: [ParsedChange], gitRoot: String) -> ChangesResult {
    var tree: [String: Any] = [:]
    var expandedPaths: Set<String> = []

    for change in changes {
      let components = change.relativePath.components(separatedBy: "/")
      let file = GitChangedFile(
        path: change.fullPath,
        name: components.last ?? "",
        status: change.status,
        diff: getDiff(for: change.relativePath, in: gitRoot, status: change.status)
      )

      tree = insertIntoTree(tree, components: components, file: file, gitRoot: gitRoot)

      // Mark parent directories as expanded
      var currentPath = gitRoot
      for component in components.dropLast() {
        currentPath = (currentPath as NSString).appendingPathComponent(component)
        expandedPaths.insert(currentPath)
      }
    }

    let items = convertTreeToItems(tree, gitRoot: gitRoot)
    return ChangesResult(items: items, expandedPaths: expandedPaths)
  }

  /// Insert a file into the tree at the correct path
  private static func insertIntoTree(
    _ tree: [String: Any],
    components: [String],
    file: GitChangedFile,
    gitRoot: String
  ) -> [String: Any] {
    var result = tree
    guard !components.isEmpty else { return result }

    let firstComponent = components[0]
    let currentPath = (gitRoot as NSString).appendingPathComponent(firstComponent)

    if components.count == 1 {
      // Insert file directly
      result[firstComponent] = file
    } else {
      // Navigate or create subdirectory
      var subTree = (result[firstComponent] as? [String: Any]) ?? [:]
      subTree = insertIntoTree(subTree, components: Array(components.dropFirst()), file: file, gitRoot: currentPath)
      result[firstComponent] = subTree
    }

    return result
  }

  /// Convert dictionary tree to array of GitChangedFile items
  private static func convertTreeToItems(_ tree: [String: Any], gitRoot: String) -> [GitChangedFile] {
    var items: [GitChangedFile] = []

    // Sort: directories first, then alphabetically
    let sortedKeys = tree.keys.sorted { lhs, rhs in
      let lhsIsDir = tree[lhs] is [String: Any]
      let rhsIsDir = tree[rhs] is [String: Any]

      if lhsIsDir != rhsIsDir {
        return lhsIsDir
      }
      return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    for key in sortedKeys {
      let fullPath = (gitRoot as NSString).appendingPathComponent(key)

      if let file = tree[key] as? GitChangedFile {
        items.append(file)
      } else if let subTree = tree[key] as? [String: Any] {
        let children = convertTreeToItems(subTree, gitRoot: fullPath)
        items.append(GitChangedFile(path: fullPath, name: key, children: children))
      }
    }

    return items
  }

  // MARK: - Diff Generation

  /// Generate diff for a file based on its status
  private static func getDiff(for filePath: String, in gitRoot: String, status: GitFileStatus) -> String {
    switch status {
    case .untracked:
      return generateUntrackedFileDiff(filePath, in: gitRoot)
    case .deleted:
      return runGitDiff(["diff", "--cached", "--", filePath], in: gitRoot)
    default:
      return runGitDiff(["diff", "--", filePath], in: gitRoot)
    }
  }

  /// Generate a unified diff format for untracked files
  private static func generateUntrackedFileDiff(_ filePath: String, in gitRoot: String) -> String {
    let fullPath = (gitRoot as NSString).appendingPathComponent(filePath)
    guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
      return ""
    }

    let lines = content.components(separatedBy: "\n")
    var diff = "diff --git a/\(filePath) b/\(filePath)\n"
    diff += "new file mode 100644\n"
    diff += "--- /dev/null\n"
    diff += "+++ b/\(filePath)\n"
    diff += "@@ -0,0 +1,\(lines.count) @@\n"

    for line in lines {
      diff += "+\(line)\n"
    }

    return diff
  }

  /// Run git diff command and return output
  private static func runGitDiff(_ arguments: [String], in gitRoot: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: gitRoot)

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return ""
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  }
}
