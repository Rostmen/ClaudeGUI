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

/// Git worktree operations via `Process()`.
/// These run BEFORE any Ghostty surface is created, so SIGCHLD deadlock does not apply.
enum WorktreeService {

  enum WorktreeError: LocalizedError {
    case gitNotFound
    case worktreeCreationFailed(String)
    case gitInitFailed(String)
    case destinationAlreadyExists(String)

    var errorDescription: String? {
      switch self {
      case .gitNotFound:
        return "Git executable not found at /usr/bin/git"
      case .worktreeCreationFailed(let msg):
        return "Failed to create worktree: \(msg)"
      case .gitInitFailed(let msg):
        return "Failed to initialize git repository: \(msg)"
      case .destinationAlreadyExists(let path):
        return "Destination already exists: \(path)"
      }
    }
  }

  private static let gitPath = "/usr/bin/git"

  /// Creates a worktree at `destinationPath` with a new branch from `baseBranch`.
  /// Runs: `git worktree add -b <newBranch> <destinationPath> <baseBranch>`
  static func createWorktree(
    repoPath: String,
    newBranch: String,
    baseBranch: String,
    destinationPath: String
  ) throws {
    guard FileManager.default.fileExists(atPath: gitPath) else {
      throw WorktreeError.gitNotFound
    }
    if FileManager.default.fileExists(atPath: destinationPath) {
      throw WorktreeError.destinationAlreadyExists(destinationPath)
    }

    let result = try runGit(
      ["worktree", "add", "-b", newBranch, destinationPath, baseBranch],
      in: repoPath
    )
    if result.exitCode != 0 {
      throw WorktreeError.worktreeCreationFailed(result.stderr)
    }
  }

  /// Initializes a new git repository at `path`.
  static func initGitRepo(at path: String) throws {
    guard FileManager.default.fileExists(atPath: gitPath) else {
      throw WorktreeError.gitNotFound
    }

    // git init
    let initResult = try runGit(["init"], in: path)
    if initResult.exitCode != 0 {
      throw WorktreeError.gitInitFailed(initResult.stderr)
    }

    // Initial commit so worktree creation has a valid base
    _ = try runGit(["commit", "--allow-empty", "-m", "Initial commit"], in: path)
  }

  /// Finds the git working tree root (the directory containing `.git/`).
  static func findRepoRoot(from path: String) -> String? {
    var current = path
    while current != "/" {
      let candidate = (current as NSString).appendingPathComponent(".git")
      if FileManager.default.fileExists(atPath: candidate) {
        return current
      }
      current = (current as NSString).deletingLastPathComponent
    }
    return nil
  }

  /// Suggests a default worktree destination path under `<repoRoot>/.claude/worktrees/`.
  static func defaultWorktreePath(repoRoot: String, branchName: String) -> String {
    let safeName = branchName.replacingOccurrences(of: "/", with: "-")
    return (repoRoot as NSString)
      .appendingPathComponent(".claude/worktrees/\(safeName)")
  }

  // MARK: - Private

  private struct GitResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
  }

  private static func runGit(_ args: [String], in workingDirectory: String) throws -> GitResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: gitPath)
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return GitResult(
      exitCode: process.terminationStatus,
      stdout: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      stderr: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    )
  }
}
