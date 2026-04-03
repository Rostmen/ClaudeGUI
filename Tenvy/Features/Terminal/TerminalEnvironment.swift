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
  /// - Parameter terminalId: If non-nil, sets `TENVY_TERMINAL_ID` so the hook script
  ///   can include it in events for reliable session ID mapping. Pass nil for plain terminals.
  static func build(terminalId: String? = nil) -> [String] {
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
    // Set terminal ID for hook event mapping (Claude sessions only, not plain terminals)
    if let terminalId {
      env.setVariable("TENVY_TERMINAL_ID", value: terminalId)
    }
    return env
  }

  /// Returns the user's login shell (e.g. /bin/zsh).
  static var loginShell: String {
    ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
  }

  /// Wraps a claude command in a login shell invocation so that ~/.zprofile is
  /// sourced before claude runs (`-l`). The shell init script (configured in
  /// Settings, or overridden per-split) runs before `exec` — avoids using `-i`
  /// which triggers /etc/zshrc terminal key-binding setup and causes errors
  /// without a TTY.
  /// `exec` replaces the shell with claude at the same PID — process tracking is unaffected.
  ///
  /// When `currentDirectory` is provided the `cd` runs inside the child shell,
  /// making the working-directory change process-local and thread-safe (no global
  /// `FileManager.changeCurrentDirectoryPath` mutation).
  static func shellArgs(
    executable: String,
    args: [String],
    currentDirectory: String? = nil,
    initScript: String? = nil
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

    let initClause = Self.buildInitClause(initScript)
    let command = "\(cdClause)\(initClause)exec \(claudeCommand)"
    return (loginShell, ["-l", "-c", command])
  }

  /// Returns shell args for a plain login shell (no claude).
  /// Used for "plain terminal" split panes.
  static func plainShellArgs(
    currentDirectory: String? = nil,
    initScript: String? = nil
  ) -> (executable: String, args: [String]) {
    let cdClause: String
    if let dir = currentDirectory {
      let escaped = dir.replacingOccurrences(of: "'", with: "'\\''")
      cdClause = "cd '\(escaped)' || exit 1; "
    } else {
      cdClause = ""
    }
    let initClause = Self.buildInitClause(initScript)
    let command = "\(cdClause)\(initClause)exec \(loginShell)"
    return (loginShell, ["-l", "-c", command])
  }

  /// Builds the init script clause for shell commands.
  /// Uses the provided override, or falls back to the global setting.
  private static func buildInitClause(_ override: String?) -> String {
    let script = (override ?? AppSettings.shared.shellInitScript)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !script.isEmpty else { return "" }
    return script + " "
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
