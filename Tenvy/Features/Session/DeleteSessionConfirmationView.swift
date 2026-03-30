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

/// Confirmation dialog for deleting a session, with an option to remove the worktree folder.
struct DeleteSessionConfirmationView: View {
  let session: ClaudeSession
  @Binding var removeWorktreeFolder: Bool
  let onDelete: () -> Void
  let onCancel: () -> Void

  private var isWorktreeSession: Bool {
    session.workingDirectory != session.projectPath
  }

  var body: some View {
    VStack(spacing: 16) {
      // Warning icon
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 36))
        .foregroundStyle(.red)

      Text("Delete Session")
        .font(.headline)

      Text("Are you sure you want to delete \"\(session.title)\"? This action is permanent and cannot be undone.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if isWorktreeSession {
        Divider()

        HStack {
          Toggle("Also remove worktree folder", isOn: $removeWorktreeFolder)
            .font(.subheadline)

          Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .help("Removes the git worktree and deletes the folder at:\n\(session.workingDirectory)\n\nThis runs \"git worktree remove\" and permanently deletes all files in that directory.")
        }

        if removeWorktreeFolder {
          HStack(spacing: 6) {
            Image(systemName: "folder.badge.minus")
              .foregroundStyle(.red)
              .font(.caption)
            Text(session.workingDirectory)
              .font(.caption)
              .foregroundStyle(.red)
              .lineLimit(1)
              .truncationMode(.head)
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.red.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
      }

      HStack(spacing: 12) {
        Button("Cancel") {
          onCancel()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button(role: .destructive) {
          onDelete()
        } label: {
          Text("Delete")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 380)
  }
}

#Preview("Regular Session") {
  DeleteSessionConfirmationView(
    session: ClaudeSession(
      id: "1",
      title: "Test Session",
      projectPath: "/Users/user/Projects/MyApp",
      workingDirectory: "/Users/user/Projects/MyApp",
      lastModified: Date(),
      filePath: nil,
      isNewSession: false
    ),
    removeWorktreeFolder: .constant(false),
    onDelete: {},
    onCancel: {}
  )
}

#Preview("Worktree Session") {
  DeleteSessionConfirmationView(
    session: ClaudeSession(
      id: "2",
      title: "Feature Branch",
      projectPath: "/Users/user/Projects/MyApp",
      workingDirectory: "/Users/user/Projects/MyApp/.claude/worktrees/feature-branch",
      lastModified: Date(),
      filePath: nil,
      isNewSession: false
    ),
    removeWorktreeFolder: .constant(true),
    onDelete: {},
    onCancel: {}
  )
}
