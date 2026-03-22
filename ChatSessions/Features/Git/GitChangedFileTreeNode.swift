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

/// Recursive tree node for git changes with controlled expansion
struct GitChangedFileTreeNode: View {
  let item: GitChangedFile
  @Binding var expandedItems: Set<String>
  @Binding var selectedItem: GitChangedFile?
  @Binding var selectedFile: GitChangedFile?

  private var isExpanded: Binding<Bool> {
    Binding(
      get: { expandedItems.contains(item.path) },
      set: { newValue in
        if newValue {
          expandedItems.insert(item.path)
        } else {
          expandedItems.remove(item.path)
        }
      }
    )
  }

  var body: some View {
    if item.isDirectory, let children = item.children {
      DisclosureGroup(isExpanded: isExpanded) {
        ForEach(children) { child in
          GitChangedFileTreeNode(
            item: child,
            expandedItems: $expandedItems,
            selectedItem: $selectedItem,
            selectedFile: $selectedFile
          )
        }
      } label: {
        GitChangedFileRow(
          item: item,
          isExpanded: isExpanded.wrappedValue,
          isSelected: selectedItem?.path == item.path
        )
        .contentShape(Rectangle())
        .onTapGesture {
          selectedItem = item
          selectedFile = nil
        }
      }
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      .listRowSeparator(.hidden)
    } else {
      GitChangedFileRow(
        item: item,
        isExpanded: false,
        isSelected: selectedItem?.path == item.path
      )
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      .listRowSeparator(.hidden)
      .contentShape(Rectangle())
      .onTapGesture {
        selectedItem = item
        selectedFile = item
      }
    }
  }
}

#Preview {
  @Previewable @State var expandedItems: Set<String> = []
  @Previewable @State var selectedItem: GitChangedFile?
  @Previewable @State var selectedFile: GitChangedFile?

  let sampleItem = GitChangedFile(
    path: "/path/to/Sources",
    name: "Sources",
    children: [
      GitChangedFile(path: "/path/to/Sources/main.swift", name: "main.swift", status: .modified, diff: ""),
      GitChangedFile(path: "/path/to/Sources/App.swift", name: "App.swift", status: .added, diff: "")
    ]
  )

  List {
    GitChangedFileTreeNode(
      item: sampleItem,
      expandedItems: $expandedItems,
      selectedItem: $selectedItem,
      selectedFile: $selectedFile
    )
  }
  .frame(width: 280, height: 200)
}
