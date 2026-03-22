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

  /// Build environment variables array for terminal process
  static func build() -> [String] {
    let environment = ProcessInfo.processInfo.environment
    var env: [String] = environment.map { "\($0.key)=\($0.value)" }

    // Ensure PATH includes common locations
    if let path = environment["PATH"] {
      let newPath = additionalPaths.joined(separator: ":") + ":" + path
      env.setVariable("PATH", value: newPath)
    }

    // Set terminal variables
    env.setVariable("TERM", value: "xterm-256color")
    env.setVariable("COLORTERM", value: "truecolor")
    env.setVariable("TERM_PROGRAM", value: "ChatSessions")
    env.setVariable("TERM_PROGRAM_VERSION", value: "1.0")

    return env
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
