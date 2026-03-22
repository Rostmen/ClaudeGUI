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

struct FileRowView: View {
  let item: FileItem
  let isExpanded: Bool
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: iconName)
        .foregroundColor(iconColor)
        .font(.system(size: 12))
        .frame(width: 14)

      Text(item.name)
        .font(.system(size: 12))
        .foregroundColor(isSelected ? .white : ClaudeTheme.textPrimary)
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer()

      if let status = item.gitStatus {
        Text(status.rawValue)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(ClaudeTheme.textSecondary)
          .frame(width: 14)
      }
    }
    .padding(.horizontal, 0)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(isSelected ? Color.accentColor.opacity(0.8) : Color.clear)
    )
    .contentShape(Rectangle())
  }

  private var iconName: String {
    if item.isDirectory {
      return "folder.fill"
    }
    return fileIcon(for: item.name)
  }

  private var iconColor: Color {
    if item.isDirectory {
      return .blue
    }
    return fileIconColor(for: item.name)
  }

  private func fileIcon(for filename: String) -> String {
    let ext = (filename as NSString).pathExtension.lowercased()
    switch ext {
    case "swift":
      return "swift"
    case "js", "ts", "jsx", "tsx":
      return "doc.text"
    case "json":
      return "curlybraces"
    case "md", "markdown":
      return "doc.richtext"
    case "png", "jpg", "jpeg", "gif", "svg":
      return "photo"
    case "xcodeproj", "xcworkspace":
      return "hammer"
    case "plist":
      return "list.bullet.rectangle"
    default:
      return "doc"
    }
  }

  private func fileIconColor(for filename: String) -> Color {
    let ext = (filename as NSString).pathExtension.lowercased()
    switch ext {
    case "swift":
      return .orange
    case "js", "ts", "jsx", "tsx":
      return .yellow
    case "json":
      return .green
    case "md", "markdown":
      return .blue
    case "png", "jpg", "jpeg", "gif", "svg":
      return .purple
    default:
      return ClaudeTheme.textSecondary
    }
  }

}

#Preview("File Row - Swift File") {
  FileRowView(
    item: FileItem(name: "ContentView.swift", path: "/path/to/ContentView.swift", isDirectory: false, children: nil, gitStatus: nil),
    isExpanded: false,
    isSelected: false
  )
  .padding()
  .background(Color.black.opacity(0.8))
}

#Preview("File Row - Modified") {
  FileRowView(
    item: FileItem(name: "ModifiedFile.swift", path: "/path/to/ModifiedFile.swift", isDirectory: false, children: nil, gitStatus: .modified),
    isExpanded: false,
    isSelected: false
  )
  .padding()
  .background(Color.black.opacity(0.8))
}

#Preview("File Row - Selected") {
  FileRowView(
    item: FileItem(name: "SelectedFile.swift", path: "/path/to/SelectedFile.swift", isDirectory: false, children: nil, gitStatus: .modified),
    isExpanded: false,
    isSelected: true
  )
  .padding()
  .background(Color.black.opacity(0.8))
}

#Preview("File Row - Folder") {
  FileRowView(
    item: FileItem(name: "Views", path: "/path/to/Views", isDirectory: true, children: [], gitStatus: .modified),
    isExpanded: true,
    isSelected: false
  )
  .padding()
  .background(Color.black.opacity(0.8))
}
