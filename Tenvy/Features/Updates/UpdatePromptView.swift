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

/// Bottom-right overlay prompt shown when a newer version of Tenvy is available
struct UpdatePromptView: View {
  @State private var updateService = UpdateService.shared

  var onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      switch updateService.updateState {
      case .idle:
        idleContent
      case .installing:
        installingContent
      case .success:
        successContent
      case .failed(let message):
        failedContent(message: message)
      }
    }
    .padding(16)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
  }

  private var idleContent: some View {
    VStack(spacing: 16) {
      HStack {
        Image(systemName: "arrow.down.circle.fill")
          .font(.title2)
          .foregroundStyle(.blue)
        Text("Update Available")
          .font(.headline)
        Spacer()
        Button {
          updateService.shouldShowPrompt = false
          onDismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }

      Text("Tenvy \(updateService.latestVersion ?? "") is available. Install the latest version to get new features and bug fixes.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 12) {
        Button("Later") {
          updateService.shouldShowPrompt = false
          onDismiss()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)

        Spacer()

        Button("Update") {
          updateService.performUpdate()
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private var installingContent: some View {
    HStack(spacing: 12) {
      ProgressView()
        .scaleEffect(0.8)
      Text("Installing update…")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
    }
  }

  private var successContent: some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text("Restarting…")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
    }
  }

  private func failedContent(message: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Update failed")
          .font(.headline)
        Spacer()
        Button {
          updateService.shouldShowPrompt = false
          updateService.updateState = .idle
          onDismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

#Preview("Update Available") {
  UpdatePromptView {
    print("Dismissed")
  }
  .frame(width: 400)
  .padding()
  .background(.black.opacity(0.3))
}
