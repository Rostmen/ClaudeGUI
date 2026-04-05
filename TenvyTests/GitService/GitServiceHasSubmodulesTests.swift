// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

struct GitServiceHasSubmodulesTests {

  private let gitService = GitService(settings: AppSettings.shared)

  private func makeTempDir() throws -> String {
    let path = NSTemporaryDirectory() + "GitServiceHasSubmodules-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  @Test("returns true when .gitmodules exists and is non-empty")
  func nonEmptyGitmodules() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    let path = (tmp as NSString).appendingPathComponent(".gitmodules")
    try "[submodule \"lib\"]\n\tpath = lib\n\turl = https://example.com/lib.git\n"
      .write(toFile: path, atomically: true, encoding: .utf8)

    #expect(gitService.hasSubmodules(repoRoot: tmp) == true)
  }

  @Test("returns false when .gitmodules does not exist")
  func noGitmodules() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    #expect(gitService.hasSubmodules(repoRoot: tmp) == false)
  }

  @Test("returns false when .gitmodules is empty")
  func emptyGitmodules() throws {
    let tmp = try makeTempDir()
    defer { cleanup(tmp) }

    let path = (tmp as NSString).appendingPathComponent(".gitmodules")
    try "".write(toFile: path, atomically: true, encoding: .utf8)

    #expect(gitService.hasSubmodules(repoRoot: tmp) == false)
  }
}
