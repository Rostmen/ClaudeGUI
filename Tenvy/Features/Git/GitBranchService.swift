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

/// Resolves the current git branch for a given directory by reading `.git/HEAD` directly.
/// No subprocess is spawned — safe to use alongside Ghostty (avoids SIGCHLD deadlock).
enum GitBranchService {

  /// Returns the current branch name, or `nil` if the path is not inside a git repo.
  /// For detached HEAD, returns the short SHA.
  static func currentBranch(at path: String) -> String? {
    guard let gitDir = findGitDir(from: path) else { return nil }
    let headPath = (gitDir as NSString).appendingPathComponent("HEAD")

    guard let contents = try? String(contentsOfFile: headPath, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }

    // Symbolic ref: "ref: refs/heads/main"
    let refPrefix = "ref: refs/heads/"
    if contents.hasPrefix(refPrefix) {
      return String(contents.dropFirst(refPrefix.count))
    }

    // Detached HEAD — return short SHA
    if contents.count >= 7 {
      return String(contents.prefix(7))
    }

    return nil
  }

  /// Lists all local branch names by reading the filesystem directly.
  /// Reads `.git/refs/heads/` recursively + `.git/packed-refs` for packed branches.
  /// No subprocess — safe alongside Ghostty.
  static func listLocalBranches(at path: String) -> [String] {
    guard let gitDir = findGitDir(from: path) else { return [] }

    // For worktree git dirs (e.g. .git/worktrees/<name>), refs/heads lives in
    // the main repo's .git, not the worktree's. Resolve via commondir if present.
    let refsGitDir: String
    let commondirPath = (gitDir as NSString).appendingPathComponent("commondir")
    if let commondir = try? String(contentsOfFile: commondirPath, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines) {
      refsGitDir = commondir.hasPrefix("/")
        ? commondir
        : (gitDir as NSString).appendingPathComponent(commondir)
    } else {
      refsGitDir = gitDir
    }

    var branches: Set<String> = []

    // 1. Loose refs from refs/heads/
    let refsHeadsPath = (refsGitDir as NSString).appendingPathComponent("refs/heads")
    if let enumerator = FileManager.default.enumerator(atPath: refsHeadsPath) {
      while let relativePath = enumerator.nextObject() as? String {
        let fullPath = (refsHeadsPath as NSString).appendingPathComponent(relativePath)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
        if !isDir.boolValue {
          branches.insert(relativePath)
        }
      }
    }

    // 2. Packed refs
    let packedRefsPath = (refsGitDir as NSString).appendingPathComponent("packed-refs")
    if let contents = try? String(contentsOfFile: packedRefsPath, encoding: .utf8) {
      let prefix = "refs/heads/"
      for line in contents.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("^") else { continue }
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let ref = String(parts[1])
        if ref.hasPrefix(prefix) {
          branches.insert(String(ref.dropFirst(prefix.count)))
        }
      }
    }

    return branches.sorted()
  }

  /// Walks up from `path` to find the `.git` directory (or file for worktrees).
  static func findGitDir(from path: String) -> String? {
    var current = path
    while current != "/" {
      let candidate = (current as NSString).appendingPathComponent(".git")
      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir) {
        if isDir.boolValue {
          return candidate
        }
        // `.git` file (worktree) — read the gitdir pointer
        if let content = try? String(contentsOfFile: candidate, encoding: .utf8)
          .trimmingCharacters(in: .whitespacesAndNewlines),
          content.hasPrefix("gitdir: ") {
          let gitdir = String(content.dropFirst("gitdir: ".count))
          // Resolve relative paths
          if gitdir.hasPrefix("/") {
            return gitdir
          }
          return (current as NSString).appendingPathComponent(gitdir)
        }
      }
      current = (current as NSString).deletingLastPathComponent
    }
    return nil
  }
}
