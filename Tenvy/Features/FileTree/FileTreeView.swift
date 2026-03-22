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

import SwiftUI

struct FileTreeView: View {
  let rootPath: String
  @Binding var selectedFilePath: String?
  @State private var expandedItems: Set<String> = []
  @State private var selectedItem: FileItem?
  @State private var hasLoadedExpandedPaths = false

  private let cache = FileTreeCache.shared

  init(rootPath: String, selectedFilePath: Binding<String?>) {
    self.rootPath = rootPath
    self._selectedFilePath = selectedFilePath
  }

  /// Get cached tree items or empty if loading
  private var rootItems: [FileItem] {
    cache.getTree(for: rootPath)?.items ?? []
  }

  private var isLoading: Bool {
    cache.isLoading(rootPath) && rootItems.isEmpty
  }

  var body: some View {
    Group {
      if isLoading {
        VStack(spacing: 12) {
          ProgressView()
            .scaleEffect(0.8)
          Text("Loading files...")
            .font(.caption)
            .foregroundColor(ClaudeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(rootItems) { item in
            FileTreeNode(
              item: item,
              expandedItems: $expandedItems,
              selectedItem: $selectedItem,
              selectedFilePath: $selectedFilePath
            )
          }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 20)
        .scrollContentBackground(.hidden)
      }
    }
    .task {
      // Trigger cache load
      _ = cache.getTree(for: rootPath)
    }
    .onChange(of: rootPath) { _, _ in
      saveExpandedPaths()
      hasLoadedExpandedPaths = false
      selectedItem = nil
      // Trigger cache load for new path
      _ = cache.getTree(for: rootPath)
    }
    .onChange(of: rootItems) { _, newItems in
      // Load expanded paths when tree becomes available
      if !hasLoadedExpandedPaths && !newItems.isEmpty {
        loadExpandedPaths()
        hasLoadedExpandedPaths = true

        // If no persisted state, expand root by default
        if expandedItems.isEmpty, let firstItem = newItems.first {
          expandedItems.insert(firstItem.path)
        }
      }
    }
    .onChange(of: expandedItems) { _, _ in
      saveExpandedPaths()
    }
  }

  private func loadExpandedPaths() {
    expandedItems = ExpansionStateManager.loadExpandedPaths(for: rootPath)
  }

  private func saveExpandedPaths() {
    ExpansionStateManager.saveExpandedPaths(expandedItems, for: rootPath)
  }
}

#Preview {
  @Previewable @State var selectedFilePath: String?

  FileTreeView(
    rootPath: NSHomeDirectory(),
    selectedFilePath: $selectedFilePath
  )
  .frame(width: 280, height: 400)
  .background(Color.black.opacity(0.8))
}
