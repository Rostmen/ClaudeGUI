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

/// Prompt view for installing hooks
struct HookInstallationPromptView: View {
  @State private var installationService = HookInstallationService.shared
  @State private var isInstalling = false
  @State private var installationError: String?
  @State private var installationSuccess = false

  var onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      // Header
      HStack {
        Image(systemName: "bell.badge")
          .font(.title2)
          .foregroundStyle(.yellow)

        Text("Enable Session State Tracking")
          .font(.headline)

        Spacer()

        Button {
          installationService.dismissPromptTemporarily()
          onDismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }

      // Description
      Text("Install Claude Code hooks to see real-time session states like \"Thinking...\", \"Reading file...\", and \"Waiting for input\" in the sidebar.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      // Error message
      if let error = installationError {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(8)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
      }

      // Success message
      if installationSuccess {
        HStack {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Hooks installed and sessions restarted!")
            .font(.caption)
            .foregroundStyle(.green)
        }
        .padding(8)
        .background(.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
      }

      // Buttons
      HStack(spacing: 12) {
        Button("Don't Ask Again") {
          installationService.dismissPromptPermanently()
          onDismiss()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)

        Spacer()

        if installationSuccess {
          Button("Done") {
            onDismiss()
          }
          .buttonStyle(.borderedProminent)
        } else {
          Button {
            install()
          } label: {
            if isInstalling {
              ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 8)
            } else {
              Text("Install Hooks")
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isInstalling)
        }
      }
    }
    .padding(16)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
  }

  private func install() {
    isInstalling = true
    installationError = nil

    Task {
      let result = await installationService.installHooks()

      await MainActor.run {
        isInstalling = false

        switch result {
        case .success:
          // Restart active sessions to apply hooks
          TerminalRegistry.shared.restartAllSessions()
          installationSuccess = true
        case .failure(let error):
          installationError = error.localizedDescription
        }
      }
    }
  }
}

#Preview {
  HookInstallationPromptView {
    print("Dismissed")
  }
  .frame(width: 400)
  .padding()
  .background(.black.opacity(0.3))
}
