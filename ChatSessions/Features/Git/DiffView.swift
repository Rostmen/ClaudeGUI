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
import gitdiff

struct DiffView: View {
  let file: GitChangedFile

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header with file name and status
      HStack {
        Text(file.name)
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(ClaudeTheme.textPrimary)

        Spacer()

        Text(statusLabel)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(statusColor)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(statusColor.opacity(0.2))
          )
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color.black.opacity(0.3))

      Divider()
        .background(ClaudeTheme.textSecondary.opacity(0.3))

      // Diff content
      if let diff = file.diff, !diff.isEmpty {
        ScrollView {
          DiffRenderer(diffText: diff)
            .diffTheme(.dark)
            .diffFont(size: 12, weight: .regular)
            .diffLineSpacing(.comfortable)
            .padding(8)
        }
      } else {
        VStack(spacing: 12) {
          Image(systemName: "doc.text")
            .font(.system(size: 32))
            .foregroundColor(ClaudeTheme.textSecondary)
          Text("No diff available")
            .font(.subheadline)
            .foregroundColor(ClaudeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color(hex: "#1E1E2E"))
  }

  private var statusLabel: String {
    guard let status = file.status else { return "Unknown" }
    switch status {
    case .modified:
      return "Modified"
    case .added:
      return "Added"
    case .deleted:
      return "Deleted"
    case .renamed:
      return "Renamed"
    case .untracked:
      return "Untracked"
    case .staged:
      return "Staged"
    }
  }

  private var statusColor: Color {
    guard let status = file.status else { return .gray }
    switch status {
    case .modified:
      return .orange
    case .added, .staged:
      return .green
    case .deleted:
      return .red
    case .renamed:
      return .blue
    case .untracked:
      return .gray
    }
  }
}

#Preview {
  DiffView(
    file: GitChangedFile(
      path: "/path/to/file.swift",
      name: "file.swift",
      status: .modified,
      diff: """
        @@ -1,5 +1,6 @@
         import SwiftUI

        -let oldValue = "Hello"
        +let newValue = "World"
        +let anotherValue = "Test"
         let unchanged = true
        """
    )
  )
  .frame(width: 600, height: 400)
}
