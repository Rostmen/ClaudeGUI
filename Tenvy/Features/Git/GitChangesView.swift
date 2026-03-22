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

struct GitChangesView: View {
  let rootPath: String
  @Binding var selectedFile: GitChangedFile?

  @State private var rootItems: [GitChangedFile] = []
  @State private var expandedItems: Set<String> = []
  @State private var isLoading = true
  @State private var selectedItem: GitChangedFile?

  var body: some View {
    Group {
      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if rootItems.isEmpty {
        NoChangesView()
      } else {
        List {
          ForEach(rootItems) { item in
            GitChangedFileTreeNode(
              item: item,
              expandedItems: $expandedItems,
              selectedItem: $selectedItem,
              selectedFile: $selectedFile
            )
          }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 20)
        .scrollContentBackground(.hidden)
      }
    }
    .task {
      await loadChangedFiles()
    }
    .onChange(of: rootPath) { _, _ in
      Task {
        await loadChangedFiles()
      }
    }
  }

  private func loadChangedFiles() async {
    isLoading = true

    let result = await Task.detached {
      GitChangesService.loadChanges(at: rootPath)
    }.value

    await MainActor.run {
      rootItems = result.items
      expandedItems = result.expandedPaths
      isLoading = false
    }
  }
}

// MARK: - No Changes View

private struct NoChangesView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "checkmark.circle")
        .font(.system(size: 32))
        .foregroundColor(.green)
      Text("No changes")
        .font(.subheadline)
        .foregroundColor(ClaudeTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  @Previewable @State var selectedFile: GitChangedFile?

  GitChangesView(
    rootPath: NSHomeDirectory(),
    selectedFile: $selectedFile
  )
  .frame(width: 280, height: 400)
  .background(Color.black.opacity(0.8))
}
