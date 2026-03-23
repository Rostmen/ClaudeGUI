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
  /// Additional paths to add to PATH for finding claude and other tools
  private static let additionalPaths = [
    "/usr/local/bin",
    "/opt/homebrew/bin",
    NSHomeDirectory() + "/.local/bin"
  ]

  /// Build environment variables array for terminal process.
  /// Uses the login shell environment so .zprofile / .zshrc vars (auth tokens, PATH) are available.
  static func build() -> [String] {
    // Prefer login shell env — GUI apps don't source shell config files, so
    // tokens and PATH entries set in .zprofile/.zshrc would be missing otherwise.
    let base = loginShellEnvironment() ?? ProcessInfo.processInfo.environment
    var env: [String] = base.map { "\($0.key)=\($0.value)" }

    // Ensure PATH includes common locations (in case shell env didn't add them)
    if let path = base["PATH"] {
      let newPath = additionalPaths.joined(separator: ":") + ":" + path
      env.setVariable("PATH", value: newPath)
    }

    // Set terminal variables
    env.setVariable("TERM", value: "xterm-256color")
    env.setVariable("COLORTERM", value: "truecolor")
    env.setVariable("TERM_PROGRAM", value: "Tenvy")
    env.setVariable("TERM_PROGRAM_VERSION", value: "1.0")

    return env
  }

  /// Runs the user's login shell with `-l -c env` to capture the full shell environment.
  /// Falls back to nil if the shell can't be launched, allowing the caller to use the app env.
  private static func loginShellEnvironment() -> [String: String]? {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: shell)
    task.arguments = ["-l", "-c", "env"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      return nil
    }

    guard task.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }

    var result: [String: String] = [:]
    for line in output.components(separatedBy: .newlines) where !line.isEmpty {
      // Split on the first `=` only — values can contain `=`
      guard let separatorIndex = line.firstIndex(of: "=") else { continue }
      let key = String(line[line.startIndex..<separatorIndex])
      let value = String(line[line.index(after: separatorIndex)...])
      result[key] = value
    }
    return result.isEmpty ? nil : result
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
