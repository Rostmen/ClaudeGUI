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

/// Builds environment variables for terminal processes
struct TerminalEnvironment {
  /// Build the initial environment to pass to the shell process.
  /// The shell itself will source ~/.zprofile and ~/.zshrc and augment this further.
  static func build() -> [String] {
    var env: [String] = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
    env.setVariable("TERM", value: "xterm-256color")
    env.setVariable("COLORTERM", value: "truecolor")
    env.setVariable("TERM_PROGRAM", value: "Tenvy")
    env.setVariable("TERM_PROGRAM_VERSION", value: "1.0")
    // /etc/zprofile and /etc/zshrc expect LANG to be set;
    // GUI apps launched by launchd don't inherit it from the shell.
    if ProcessInfo.processInfo.environment["LANG"] == nil {
      env.setVariable("LANG", value: "en_US.UTF-8")
    }
    // Apply user-defined custom variables (set in Settings → Environment Variables)
    for (key, value) in AppSettings.shared.customEnvironmentVariables {
      env.setVariable(key, value: value)
    }
    return env
  }

  /// Returns the user's login shell (e.g. /bin/zsh).
  static var loginShell: String {
    ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
  }

  /// Wraps a claude command in a login shell invocation so that ~/.zprofile and
  /// ~/.zshrc are sourced before claude runs.
  /// `-l` sources ~/.zprofile. ~/.zshrc is sourced manually — avoids using `-i`
  /// which triggers /etc/zshrc terminal key-binding setup and causes errors without a TTY.
  /// `exec` replaces the shell with claude (same PID), so SwiftTerm tracks it correctly.
  ///
  /// When `currentDirectory` is provided the `cd` runs inside the child shell,
  /// making the working-directory change process-local and thread-safe (no global
  /// `FileManager.changeCurrentDirectoryPath` mutation).
  static func shellArgs(
    executable: String,
    args: [String],
    currentDirectory: String? = nil
  ) -> (executable: String, args: [String]) {
    let claudeCommand = ([executable] + args)
      .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
      .joined(separator: " ")

    let cdClause: String
    if let dir = currentDirectory {
      let escaped = dir.replacingOccurrences(of: "'", with: "'\\''")
      cdClause = "cd '\(escaped)' || exit 1; "
    } else {
      cdClause = ""
    }

    // Source ~/.zshrc manually (errors suppressed so /etc/zshrc side-effects don't show)
    // then exec into claude — after exec, the PTY is claude's and output is unaffected.
    let command = "\(cdClause)[ -f \"$HOME/.zshrc\" ] && source \"$HOME/.zshrc\" 2>/dev/null; exec \(claudeCommand)"
    return (loginShell, ["-l", "-c", command])
  }
}

// MARK: - Array Extension for Environment Variables

private extension Array where Element == String {
  /// Set or replace an environment variable
  mutating func setVariable(_ name: String, value: String) {
    removeAll { $0.hasPrefix("\(name)=") }
    append("\(name)=\(value)")
  }
}
