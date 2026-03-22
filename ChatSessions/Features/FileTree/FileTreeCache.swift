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

/// Cached file tree data for a directory
struct CachedFileTree {
  let rootPath: String
  let items: [FileItem]
  let gitStatus: [String: GitFileStatus]
  let loadedAt: Date
}

/// Service that loads and caches file trees in background, shared across views
@MainActor
@Observable
final class FileTreeCache {
  static let shared = FileTreeCache()

  private(set) var cache: [String: CachedFileTree] = [:]
  private(set) var loadingPaths: Set<String> = []

  private let gitStatusService = GitStatusService()

  private init() {}

  /// Get cached tree or trigger background load
  func getTree(for rootPath: String) -> CachedFileTree? {
    if let cached = cache[rootPath] {
      return cached
    }

    // Not cached, trigger background load if not already loading
    if !loadingPaths.contains(rootPath) {
      loadTreeInBackground(for: rootPath)
    }

    return nil
  }

  /// Check if a path is currently loading
  func isLoading(_ rootPath: String) -> Bool {
    loadingPaths.contains(rootPath)
  }

  /// Force refresh a tree (e.g., when files change)
  func refresh(for rootPath: String) {
    cache.removeValue(forKey: rootPath)
    loadTreeInBackground(for: rootPath)
  }

  /// Invalidate cache for a path
  func invalidate(for rootPath: String) {
    cache.removeValue(forKey: rootPath)
  }

  private func loadTreeInBackground(for rootPath: String) {
    loadingPaths.insert(rootPath)

    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self = self else { return }

      // Load git status (this is fast)
      let gitStatus = await MainActor.run {
        self.gitStatusService.getStatus(for: rootPath)
      }

      // Load file tree in background
      let items = self.loadDirectory(at: rootPath, gitStatus: gitStatus)

      let cachedTree = CachedFileTree(
        rootPath: rootPath,
        items: items,
        gitStatus: gitStatus,
        loadedAt: Date()
      )

      await MainActor.run {
        self.cache[rootPath] = cachedTree
        self.loadingPaths.remove(rootPath)
      }
    }
  }

  /// Load directory contents (runs on background thread)
  private nonisolated func loadDirectory(at path: String, gitStatus: [String: GitFileStatus]) -> [FileItem] {
    let fileManager = FileManager.default
    guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
      return []
    }

    return contents
      .filter { !$0.hasPrefix(".") } // Hide hidden files
      .sorted { lhs, rhs in
        let lhsPath = (path as NSString).appendingPathComponent(lhs)
        let rhsPath = (path as NSString).appendingPathComponent(rhs)
        let lhsIsDir = isDirectory(lhsPath)
        let rhsIsDir = isDirectory(rhsPath)

        // Directories first, then alphabetically
        if lhsIsDir != rhsIsDir {
          return lhsIsDir
        }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
      }
      .map { name in
        let fullPath = (path as NSString).appendingPathComponent(name)
        let isDir = isDirectory(fullPath)
        return FileItem(
          name: name,
          path: fullPath,
          isDirectory: isDir,
          children: isDir ? loadDirectory(at: fullPath, gitStatus: gitStatus) : nil,
          gitStatus: gitStatus[fullPath]
        )
      }
  }

  private nonisolated func isDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    return isDir.boolValue
  }
}
