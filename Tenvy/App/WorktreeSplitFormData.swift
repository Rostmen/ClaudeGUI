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

/// Form data for the worktree creation dialog.
struct WorktreeSplitFormData {
  var baseBranch: String
  var newBranchName: String
  var worktreePath: String
  var forkSession: Bool = false
  var initSubmodules: Bool = true
  var symlinkBuildArtifacts: Bool = true
  var availableBranches: [String]
  let sourceSessionId: String
  let sourceIsNewSession: Bool
  let repoRoot: String
  /// Whether the repo has .gitmodules (submodule options only shown when true)
  let hasSubmodules: Bool
  var initScript: String = AppSettings.shared.shellInitScript

  /// Pre-generated unique session ID. Used in custom worktree paths
  /// so the path includes a unique identifier before the session is created.
  let tenvySessionId: String = UUID().uuidString

  /// Whether to run `git init` (only relevant when hasGitRepo == false)
  var initGit: Bool = false

  /// Whether to create a new branch (in new-session + git flow, or after git init)
  var createBranch: Bool = false

  /// Which git mode is active: branch-only or worktree
  var gitMode: GitMode = .worktree

  enum GitMode: String, CaseIterable {
    case branch = "Branch"
    case worktree = "Worktree"
  }
}
