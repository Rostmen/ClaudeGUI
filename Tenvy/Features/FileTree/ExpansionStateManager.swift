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

/// Manages persistence of tree expansion state in UserDefaults
struct ExpansionStateManager {
  private static let keyPrefix = "FileTreeView.expandedPaths."

  /// Generate UserDefaults key for a root path
  private static func key(for rootPath: String) -> String {
    keyPrefix + rootPath.replacingOccurrences(of: "/", with: "_")
  }

  /// Load expanded paths for a root directory
  /// Only returns paths that still exist on disk
  static func loadExpandedPaths(for rootPath: String) -> Set<String> {
    let key = key(for: rootPath)
    guard let paths = UserDefaults.standard.stringArray(forKey: key) else {
      return []
    }

    // Filter to only existing paths
    let fileManager = FileManager.default
    return Set(paths.filter { fileManager.fileExists(atPath: $0) })
  }

  /// Save expanded paths for a root directory
  static func saveExpandedPaths(_ paths: Set<String>, for rootPath: String) {
    let key = key(for: rootPath)
    UserDefaults.standard.set(Array(paths), forKey: key)
  }

  /// Clear saved expansion state for a root directory
  static func clearExpandedPaths(for rootPath: String) {
    let key = key(for: rootPath)
    UserDefaults.standard.removeObject(forKey: key)
  }
}
