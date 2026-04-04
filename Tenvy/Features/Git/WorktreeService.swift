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
    case branchCreationFailed(String)
    case destinationAlreadyExists(String)

    var errorDescription: String? {
      switch self {
      case .gitNotFound:
        return "Git executable not found at /usr/bin/git"
      case .worktreeCreationFailed(let msg):
        return "Failed to create worktree: \(msg)"
      case .gitInitFailed(let msg):
        return "Failed to initialize git repository: \(msg)"
      case .branchCreationFailed(let msg):
        return "Failed to create branch: \(msg)"
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
    destinationPath: String,
    initSubmodules: Bool = true,
    symlinkBuildArtifacts: Bool = true
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

    if initSubmodules {
      // Initialize submodules in the new worktree (worktrees don't auto-init them)
      _ = try? runGit(["submodule", "update", "--init", "--recursive"], in: destinationPath)
    }

    if symlinkBuildArtifacts {
      // Symlink gitignored build artifacts from the main repo's submodules into the worktree.
      // Submodule init checks out source but not build artifacts (e.g. xcframeworks).
      symlinkSubmoduleBuildArtifacts(mainRepo: repoPath, worktree: destinationPath)
    }
  }

  /// Removes a worktree: runs `git worktree remove --force` and deletes the directory.
  static func removeWorktree(repoPath: String, worktreePath: String) throws {
    guard FileManager.default.fileExists(atPath: gitPath) else {
      throw WorktreeError.gitNotFound
    }

    let result = try runGit(
      ["worktree", "remove", "--force", worktreePath],
      in: repoPath
    )
    if result.exitCode != 0 {
      // Fallback: remove directory manually and prune
      try? FileManager.default.removeItem(atPath: worktreePath)
      _ = try? runGit(["worktree", "prune"], in: repoPath)
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

  /// Creates a new branch from `baseBranch` and checks it out.
  /// Runs: `git checkout -b <newBranch> <baseBranch>`
  static func createBranch(
    repoPath: String,
    newBranch: String,
    baseBranch: String
  ) throws {
    guard FileManager.default.fileExists(atPath: gitPath) else {
      throw WorktreeError.gitNotFound
    }
    let result = try runGit(["checkout", "-b", newBranch, baseBranch], in: repoPath)
    if result.exitCode != 0 {
      throw WorktreeError.branchCreationFailed(result.stderr)
    }
  }

  /// Finds the main git repository root (the directory containing a `.git/` **directory**).
  /// Worktrees have a `.git` **file** (with a `gitdir:` pointer) — this method skips those
  /// and keeps walking up so worktree paths are always resolved relative to the main repo.
  static func findRepoRoot(from path: String) -> String? {
    var current = path
    let fm = FileManager.default
    while current != "/" {
      let candidate = (current as NSString).appendingPathComponent(".git")
      var isDirectory: ObjCBool = false
      if fm.fileExists(atPath: candidate, isDirectory: &isDirectory) {
        if isDirectory.boolValue {
          // Real repo root — .git is a directory
          return current
        }
        // Worktree — .git is a file; keep walking up
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

  /// Whether the repository has submodules (.gitmodules file exists and is non-empty).
  static func hasSubmodules(repoRoot: String) -> Bool {
    let gitmodulesPath = (repoRoot as NSString).appendingPathComponent(".gitmodules")
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: gitmodulesPath),
          let size = attrs[.size] as? UInt64 else { return false }
    return size > 0
  }

  // MARK: - Private

  /// Finds gitignored build artifacts in the main repo's submodules and symlinks them
  /// into the worktree so it can compile without rebuilding (e.g. xcframeworks).
  private static func symlinkSubmoduleBuildArtifacts(mainRepo: String, worktree: String) {
    // Get submodule paths from the main repo
    guard let result = try? runGit(["submodule", "foreach", "--quiet", "echo $sm_path"], in: mainRepo),
          result.exitCode == 0 else { return }

    let submodulePaths = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
    let fm = FileManager.default

    for submodulePath in submodulePaths {
      let mainSubmoduleDir = (mainRepo as NSString).appendingPathComponent(submodulePath)
      let worktreeSubmoduleDir = (worktree as NSString).appendingPathComponent(submodulePath)

      // Find gitignored items in the main repo's submodule
      guard let ignored = try? runGit(
        ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory"],
        in: mainSubmoduleDir
      ), ignored.exitCode == 0 else { continue }

      let ignoredPaths = ignored.stdout.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        .filter { !$0.isEmpty }

      for ignoredItem in ignoredPaths {
        let source = (mainSubmoduleDir as NSString).appendingPathComponent(ignoredItem)
        let destination = (worktreeSubmoduleDir as NSString).appendingPathComponent(ignoredItem)

        // Only symlink if source exists in main repo and doesn't exist in worktree
        guard fm.fileExists(atPath: source), !fm.fileExists(atPath: destination) else { continue }

        // Ensure parent directory exists
        let parentDir = (destination as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        try? fm.createSymbolicLink(atPath: destination, withDestinationPath: source)
      }
    }
  }

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
