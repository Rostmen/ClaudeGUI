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
import Testing
@testable import Tenvy

// MARK: - String.defaultBranchName Tests

struct DefaultBranchNameTests {

  @Test("formats date and title correctly")
  func basicFormatting() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let date = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 14, minute: 30))!

    let result = String.defaultBranchName(from: date, title: "Fix Login Bug")
    #expect(result.hasSuffix("-fix-login-bug"))
    #expect(result.contains("2026"))
  }

  @Test("replaces spaces with hyphens")
  func spacesReplacedWithHyphens() {
    let result = String.defaultBranchName(from: Date(), title: "Add New Feature")
    #expect(!result.contains(" "))
    #expect(result.hasSuffix("-add-new-feature"))
  }

  @Test("converts to lowercase")
  func lowercased() {
    let result = String.defaultBranchName(from: Date(), title: "MyFeature")
    #expect(result.hasSuffix("-myfeature"))
    #expect(result == result.lowercased())
  }

  @Test("handles empty title")
  func emptyTitle() {
    let result = String.defaultBranchName(from: Date(), title: "")
    // Should end with just the date stamp and a trailing hyphen
    #expect(result.hasSuffix("-"))
  }

  @Test("handles title with special characters")
  func specialCharacters() {
    let result = String.defaultBranchName(from: Date(), title: "fix/bug#123")
    #expect(result.hasSuffix("-fix/bug#123"))
    #expect(result == result.lowercased())
  }
}

// MARK: - WorktreeSplitFormData Tests

struct WorktreeSplitFormDataTests {

  @Test("default values are set correctly")
  func defaults() {
    let form = WorktreeSplitFormData(
      baseBranch: "main",
      newBranchName: "feature",
      worktreePath: "/path",
      availableBranches: ["main"],
      sourceSessionId: "s1",
      sourceIsNewSession: true,
      repoRoot: "/repo",
      hasSubmodules: false
    )
    #expect(form.forkSession == false)
    #expect(form.initSubmodules == true)
    #expect(form.symlinkBuildArtifacts == true)
    #expect(form.initGit == false)
    #expect(form.createBranch == false)
    #expect(form.gitMode == .worktree)
  }

  @Test("each instance gets a unique tenvySessionId")
  func uniqueSessionIds() {
    let form1 = WorktreeSplitFormData(
      baseBranch: "main", newBranchName: "a", worktreePath: "",
      availableBranches: [], sourceSessionId: "s1",
      sourceIsNewSession: true, repoRoot: "/repo", hasSubmodules: false
    )
    let form2 = WorktreeSplitFormData(
      baseBranch: "main", newBranchName: "b", worktreePath: "",
      availableBranches: [], sourceSessionId: "s2",
      sourceIsNewSession: true, repoRoot: "/repo", hasSubmodules: false
    )
    #expect(form1.tenvySessionId != form2.tenvySessionId)
  }

  @Test("GitMode raw values match display strings")
  func gitModeRawValues() {
    #expect(WorktreeSplitFormData.GitMode.branch.rawValue == "Branch")
    #expect(WorktreeSplitFormData.GitMode.worktree.rawValue == "Worktree")
    #expect(WorktreeSplitFormData.GitMode.allCases.count == 2)
  }
}

// MARK: - PendingSplitRequest Tests

struct PendingSplitRequestTests {

  @Test("default parameters are false")
  func defaultParameters() {
    let session = ClaudeSession(
      id: "test", title: "Test", projectPath: "/p",
      workingDirectory: "/p", lastModified: Date(), filePath: nil
    )
    let request = PendingSplitRequest(
      direction: .right, sourceSession: session, hasGitRepo: true
    )
    #expect(request.isNewSessionFlow == false)
    #expect(request.isPlainTerminalSplit == false)
    #expect(request.hasGitRepo == true)
    #expect(request.direction == .right)
  }

  @Test("explicit parameters are preserved")
  func explicitParameters() {
    let session = ClaudeSession(
      id: "test", title: "Test", projectPath: "/p",
      workingDirectory: "/p", lastModified: Date(), filePath: nil
    )
    let request = PendingSplitRequest(
      direction: .down,
      sourceSession: session,
      hasGitRepo: false,
      isNewSessionFlow: true,
      isPlainTerminalSplit: true
    )
    #expect(request.isNewSessionFlow == true)
    #expect(request.isPlainTerminalSplit == true)
    #expect(request.hasGitRepo == false)
    #expect(request.direction == .down)
  }
}

// MARK: - DateFormatter.branchNameDate Tests

struct BranchNameDateFormatterTests {

  @Test("formatter uses expected date format")
  func dateFormat() {
    #expect(DateFormatter.branchNameDate.dateFormat == "MM-dd-yyyy-HH-mm")
  }

  @Test("formatter is a singleton (same instance)")
  func singleton() {
    let a = DateFormatter.branchNameDate
    let b = DateFormatter.branchNameDate
    #expect(a === b)
  }
}
