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

/// Tests for `TerminalEnvironment.shellArgs` — particularly the `currentDirectory`
/// parameter added in Fix 8 to eliminate global `cwd` mutation.
struct TerminalEnvironmentTests {

  @Test("shellArgs without currentDirectory does not include cd clause")
  func noCdClauseWhenNoDirectory() {
    let result = TerminalEnvironment.shellArgs(executable: "/usr/local/bin/claude", args: [])
    let command = result.args.last ?? ""
    #expect(!command.hasPrefix("cd "))
  }

  @Test("shellArgs with currentDirectory prepends cd clause")
  func cdClausePresentWhenDirectoryProvided() {
    let result = TerminalEnvironment.shellArgs(
      executable: "/usr/local/bin/claude",
      args: [],
      currentDirectory: "/Users/alice/my-project"
    )
    let command = result.args.last ?? ""
    #expect(command.hasPrefix("cd '/Users/alice/my-project'"))
  }

  @Test("shellArgs cd clause exits on failure")
  func cdClauseExitsOnFailure() {
    let result = TerminalEnvironment.shellArgs(
      executable: "/usr/local/bin/claude",
      args: [],
      currentDirectory: "/some/dir"
    )
    let command = result.args.last ?? ""
    #expect(command.contains("|| exit 1"))
  }

  @Test("shellArgs escapes single quotes in directory path")
  func cdClauseEscapesSingleQuotes() {
    // Directory name containing a single quote (unusual but valid on macOS)
    let dir = "/Users/alice/it's-a-project"
    let result = TerminalEnvironment.shellArgs(
      executable: "/usr/local/bin/claude",
      args: [],
      currentDirectory: dir
    )
    let command = result.args.last ?? ""
    // The single quote in "it's" must be escaped so the shell doesn't break
    #expect(command.contains("'\\''"))
  }

  @Test("shellArgs uses login shell as executable")
  func usesLoginShell() {
    let result = TerminalEnvironment.shellArgs(executable: "/usr/local/bin/claude", args: [])
    #expect(result.executable == TerminalEnvironment.loginShell)
  }

  @Test("shellArgs passes -l -c flags to shell")
  func passesLoginFlags() {
    let result = TerminalEnvironment.shellArgs(executable: "/usr/local/bin/claude", args: [])
    #expect(result.args.first == "-l")
    #expect(result.args.dropFirst().first == "-c")
  }

  @Test("shellArgs sources zshrc and execs claude")
  func sourcesZshrcAndExecs() {
    let result = TerminalEnvironment.shellArgs(
      executable: "/usr/local/bin/claude",
      args: ["--resume", "session-id"]
    )
    let command = result.args.last ?? ""
    #expect(command.contains(".zshrc"))
    #expect(command.contains("exec"))
    #expect(command.contains("claude"))
    #expect(command.contains("--resume"))
    #expect(command.contains("session-id"))
  }

  @Test("shellArgs single-quote-escapes executable path")
  func escapesExecutablePath() {
    let result = TerminalEnvironment.shellArgs(
      executable: "/path/with spaces/claude",
      args: []
    )
    let command = result.args.last ?? ""
    // The path should be single-quoted
    #expect(command.contains("'/path/with spaces/claude'"))
  }
}
