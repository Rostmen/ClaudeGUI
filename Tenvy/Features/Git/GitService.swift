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

/// Unified git service — worktree operations, branch management, and repo inspection.
/// Dependencies are injected for testability.
struct GitService {

  let settings: AppSettings
  let fileManager: FileManager

  init(settings: AppSettings, fileManager: FileManager = .default) {
    self.settings = settings
    self.fileManager = fileManager
  }

  // MARK: - Error Types

  enum GitError: LocalizedError {
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

  // MARK: - Worktree Operations

  /// Creates a worktree at `destinationPath` with a new branch from `baseBranch`.
  func createWorktree(
    repoPath: String,
    newBranch: String,
    baseBranch: String,
    destinationPath: String,
    initSubmodules: Bool = true,
    symlinkBuildArtifacts: Bool = true
  ) throws {
    guard fileManager.fileExists(atPath: Self.gitPath) else {
      throw GitError.gitNotFound
    }
    if fileManager.fileExists(atPath: destinationPath) {
      throw GitError.destinationAlreadyExists(destinationPath)
    }

    let result = try Self.runGit(
      ["worktree", "add", "-b", newBranch, destinationPath, baseBranch],
      in: repoPath
    )
    if result.exitCode != 0 {
      throw GitError.worktreeCreationFailed(result.stderr)
    }

    if initSubmodules {
      _ = try? Self.runGit(["submodule", "update", "--init", "--recursive"], in: destinationPath)
    }

    if symlinkBuildArtifacts {
      symlinkSubmoduleBuildArtifacts(mainRepo: repoPath, worktree: destinationPath)
    }
  }

  /// Removes a worktree: runs `git worktree remove --force` and deletes the directory.
  func removeWorktree(repoPath: String, worktreePath: String) throws {
    guard fileManager.fileExists(atPath: Self.gitPath) else {
      throw GitError.gitNotFound
    }

    let result = try Self.runGit(
      ["worktree", "remove", "--force", worktreePath],
      in: repoPath
    )
    if result.exitCode != 0 {
      try? fileManager.removeItem(atPath: worktreePath)
      _ = try? Self.runGit(["worktree", "prune"], in: repoPath)
    }
  }

  /// Initializes a new git repository at `path`.
  func initGitRepo(at path: String) throws {
    guard fileManager.fileExists(atPath: Self.gitPath) else {
      throw GitError.gitNotFound
    }

    let initResult = try Self.runGit(["init"], in: path)
    if initResult.exitCode != 0 {
      throw GitError.gitInitFailed(initResult.stderr)
    }

    _ = try Self.runGit(["commit", "--allow-empty", "-m", "Initial commit"], in: path)
  }

  /// Creates a new branch from `baseBranch` and checks it out.
  func createBranch(
    repoPath: String,
    newBranch: String,
    baseBranch: String
  ) throws {
    guard fileManager.fileExists(atPath: Self.gitPath) else {
      throw GitError.gitNotFound
    }
    let result = try Self.runGit(["checkout", "-b", newBranch, baseBranch], in: repoPath)
    if result.exitCode != 0 {
      throw GitError.branchCreationFailed(result.stderr)
    }
  }

  // MARK: - Worktree Path Resolution

  /// Suggests a default worktree destination path based on settings.
  func defaultWorktreePath(repoRoot: String, branchName: String, sessionId: String? = nil) -> String {
    let safeName = branchName.replacingOccurrences(of: "/", with: "-")

    switch settings.worktreeLocation {
    case .defaultClaude:
      let root = (repoRoot as NSString).appendingPathComponent(".claude/worktrees")
      return (root as NSString).appendingPathComponent(safeName)

    case .custom where !settings.customWorktreeRoot.isEmpty:
      let projectName = (repoRoot as NSString).lastPathComponent
      let sessionSuffix = sessionId.map { "-\($0.prefix(8))" } ?? ""
      return (settings.customWorktreeRoot as NSString)
        .appendingPathComponent("\(projectName)\(sessionSuffix)/\(safeName)")

    default:
      let root = (repoRoot as NSString).appendingPathComponent(".claude/worktrees")
      return (root as NSString).appendingPathComponent(safeName)
    }
  }

  /// Computes the working directory for a new worktree session, preserving the project subfolder.
  ///
  /// If the original project is in a subfolder of the git root (e.g. `<gitRoot>/ios`),
  /// the new worktree session should `cd` to `<worktreePath>/ios`.
  ///
  /// - Parameters:
  ///   - worktreePath: Destination worktree root path
  ///   - gitRoot: The git repository root
  ///   - projectPath: The original project path (may be a subfolder of gitRoot)
  /// - Returns: `worktreePath` with the project subfolder appended, or `worktreePath` as-is
  static func worktreeWorkingDirectory(
    worktreePath: String,
    gitRoot: String,
    projectPath: String
  ) -> String {
    let normalizedProject = (projectPath as NSString).standardizingPath
    let normalizedRoot = (gitRoot as NSString).standardizingPath

    guard normalizedProject.hasPrefix(normalizedRoot),
          normalizedProject.count > normalizedRoot.count else {
      return worktreePath
    }

    let subfolderOffset = String(normalizedProject.dropFirst(normalizedRoot.count + 1))
    guard !subfolderOffset.isEmpty else { return worktreePath }

    return (worktreePath as NSString).appendingPathComponent(subfolderOffset)
  }

  // MARK: - Repo Inspection

  /// Finds the main git repository root (the directory containing a `.git/` **directory**).
  /// When a `.git` **file** is found (worktree), follows the `gitdir:` pointer and resolves
  /// `commondir` to find the actual repo root — even when the worktree is in a completely
  /// different directory tree from the main repo.
  func findRepoRoot(from path: String) -> String? {
    var current = path
    while current != "/" {
      let candidate = (current as NSString).appendingPathComponent(".git")
      var isDirectory: ObjCBool = false
      if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory) {
        if isDirectory.boolValue {
          // Real repo root — .git is a directory
          return current
        }
        // Worktree — .git is a file with gitdir: pointer
        // Follow it to find the main repo
        if let repoRoot = resolveWorktreeToRepoRoot(gitFilePath: candidate, worktreeDir: current) {
          return repoRoot
        }
      }
      current = (current as NSString).deletingLastPathComponent
    }
    return nil
  }

  /// Follows a worktree's `.git` file → `gitdir:` → `commondir` to find the main repo root.
  private func resolveWorktreeToRepoRoot(gitFilePath: String, worktreeDir: String) -> String? {
    guard let content = try? String(contentsOfFile: gitFilePath, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines),
      content.hasPrefix("gitdir: ") else { return nil }

    let gitdir = String(content.dropFirst("gitdir: ".count))
    let resolvedGitDir = gitdir.hasPrefix("/")
      ? gitdir
      : (worktreeDir as NSString).appendingPathComponent(gitdir)

    // Read commondir to find the main .git directory
    let commondirPath = (resolvedGitDir as NSString).appendingPathComponent("commondir")
    if let commondir = try? String(contentsOfFile: commondirPath, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines) {
      let mainGitDir = commondir.hasPrefix("/")
        ? commondir
        : (resolvedGitDir as NSString).appendingPathComponent(commondir)
      // The repo root is the parent of the .git directory
      let normalized = (mainGitDir as NSString).standardizingPath
      return (normalized as NSString).deletingLastPathComponent
    }

    // No commondir — the gitdir itself might be under the main .git
    // e.g. /repo/.git/worktrees/name → repo root is parent of .git
    let normalized = (resolvedGitDir as NSString).standardizingPath
    // Walk up from gitdir looking for the .git directory boundary
    // Pattern: <repo>/.git/worktrees/<name> → <repo>
    if let gitRange = normalized.range(of: "/.git/") {
      return String(normalized[normalized.startIndex..<gitRange.lowerBound])
    }

    return nil
  }

  /// Whether the repository has submodules (.gitmodules file exists and is non-empty).
  func hasSubmodules(repoRoot: String) -> Bool {
    let gitmodulesPath = (repoRoot as NSString).appendingPathComponent(".gitmodules")
    guard let attrs = try? fileManager.attributesOfItem(atPath: gitmodulesPath),
          let size = attrs[.size] as? UInt64 else { return false }
    return size > 0
  }

  // MARK: - Branch Operations

  /// Returns the current branch name, or `nil` if the path is not inside a git repo.
  /// Reads `.git/HEAD` directly — no subprocess, safe alongside Ghostty.
  func currentBranch(at path: String) -> String? {
    guard let gitDir = findGitDir(from: path) else { return nil }
    let headPath = (gitDir as NSString).appendingPathComponent("HEAD")

    guard let contents = try? String(contentsOfFile: headPath, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }

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
  /// No subprocess — safe alongside Ghostty.
  func listLocalBranches(at path: String) -> [String] {
    guard let gitDir = findGitDir(from: path) else { return [] }

    let refsGitDir = resolveCommonDir(gitDir: gitDir)

    var branches: Set<String> = []

    // 1. Loose refs from refs/heads/
    let refsHeadsPath = (refsGitDir as NSString).appendingPathComponent("refs/heads")
    if let enumerator = fileManager.enumerator(atPath: refsHeadsPath) {
      while let relativePath = enumerator.nextObject() as? String {
        let fullPath = (refsHeadsPath as NSString).appendingPathComponent(relativePath)
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)
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

  /// Returns the set of branch names currently checked out in worktrees.
  /// Reads `.git/worktrees/*/HEAD` — no subprocess.
  func worktreeBranches(at path: String) -> Set<String> {
    guard let gitDir = findGitDir(from: path) else { return [] }

    let mainGitDir = resolveCommonDir(gitDir: gitDir)

    let worktreesDir = (mainGitDir as NSString).appendingPathComponent("worktrees")
    guard let entries = try? fileManager.contentsOfDirectory(atPath: worktreesDir) else {
      return []
    }

    var branches: Set<String> = []
    let refPrefix = "ref: refs/heads/"
    for entry in entries {
      let headPath = (worktreesDir as NSString)
        .appendingPathComponent(entry)
        .appending("/HEAD")
      if let contents = try? String(contentsOfFile: headPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
        contents.hasPrefix(refPrefix) {
        branches.insert(String(contents.dropFirst(refPrefix.count)))
      }
    }
    return branches
  }

  /// Checks out an existing local branch. Returns an error message on failure, nil on success.
  func checkoutBranch(_ branch: String, at path: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: Self.gitPath)
    process.arguments = ["checkout", branch]
    process.currentDirectoryURL = URL(fileURLWithPath: path)

    let stderrPipe = Pipe()
    process.standardOutput = Pipe()
    process.standardError = stderrPipe

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return error.localizedDescription
    }

    if process.terminationStatus != 0 {
      let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
      return stderr
    }
    return nil
  }

  // MARK: - Git Directory Resolution

  /// Walks up from `path` to find the `.git` directory (or file for worktrees).
  func findGitDir(from path: String) -> String? {
    var current = path
    while current != "/" {
      let candidate = (current as NSString).appendingPathComponent(".git")
      var isDir: ObjCBool = false
      if fileManager.fileExists(atPath: candidate, isDirectory: &isDir) {
        if isDir.boolValue {
          return candidate
        }
        // `.git` file (worktree) — read the gitdir pointer
        if let content = try? String(contentsOfFile: candidate, encoding: .utf8)
          .trimmingCharacters(in: .whitespacesAndNewlines),
          content.hasPrefix("gitdir: ") {
          let gitdir = String(content.dropFirst("gitdir: ".count))
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

  // MARK: - Private

  /// Resolves the commondir for worktree git dirs.
  /// Worktree git dirs (e.g. .git/worktrees/<name>) store refs in the main repo's .git.
  private func resolveCommonDir(gitDir: String) -> String {
    let commondirPath = (gitDir as NSString).appendingPathComponent("commondir")
    if let commondir = try? String(contentsOfFile: commondirPath, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines) {
      return commondir.hasPrefix("/")
        ? commondir
        : (gitDir as NSString).appendingPathComponent(commondir)
    }
    return gitDir
  }

  /// Finds gitignored build artifacts in the main repo's submodules and symlinks them
  /// into the worktree so it can compile without rebuilding (e.g. xcframeworks).
  private func symlinkSubmoduleBuildArtifacts(mainRepo: String, worktree: String) {
    guard let result = try? Self.runGit(["submodule", "foreach", "--quiet", "echo $sm_path"], in: mainRepo),
          result.exitCode == 0 else { return }

    let submodulePaths = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }

    for submodulePath in submodulePaths {
      let mainSubmoduleDir = (mainRepo as NSString).appendingPathComponent(submodulePath)
      let worktreeSubmoduleDir = (worktree as NSString).appendingPathComponent(submodulePath)

      guard let ignored = try? Self.runGit(
        ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory"],
        in: mainSubmoduleDir
      ), ignored.exitCode == 0 else { continue }

      let ignoredPaths = ignored.stdout.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        .filter { !$0.isEmpty }

      for ignoredItem in ignoredPaths {
        let source = (mainSubmoduleDir as NSString).appendingPathComponent(ignoredItem)
        let destination = (worktreeSubmoduleDir as NSString).appendingPathComponent(ignoredItem)

        guard fileManager.fileExists(atPath: source), !fileManager.fileExists(atPath: destination) else { continue }

        let parentDir = (destination as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        try? fileManager.createSymbolicLink(atPath: destination, withDestinationPath: source)
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
