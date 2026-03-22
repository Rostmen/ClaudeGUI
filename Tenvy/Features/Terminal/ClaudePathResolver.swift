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

/// Resolves the path to the claude CLI binary
struct ClaudePathResolver {
  /// Possible locations where claude might be installed
  private static let searchPaths = [
    "/usr/local/bin/claude",
    "/opt/homebrew/bin/claude",
    NSHomeDirectory() + "/.local/bin/claude",
    "/usr/bin/claude"
  ]

  /// Find the claude binary path
  /// Returns the first existing path, or "/usr/bin/env" as fallback
  static func findClaudePath() -> String {
    for path in searchPaths {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }
    // Fallback to using env to find claude in PATH
    return "/usr/bin/env"
  }

  /// Check if claude is available on the system
  static var isClaudeAvailable: Bool {
    findClaudePath() != "/usr/bin/env"
  }
}
