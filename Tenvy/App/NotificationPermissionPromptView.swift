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

/// Prompt view for requesting notification permission
struct NotificationPermissionPromptView: View {
  @State private var notificationService = NotificationService.shared

  var onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      // Header
      HStack {
        Image(systemName: "bell.badge")
          .font(.title2)
          .foregroundStyle(.orange)

        Text("Enable Notifications")
          .font(.headline)

        Spacer()

        Button {
          notificationService.dismissPromptTemporarily()
          onDismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }

      // Description
      if notificationService.authorizationDenied {
        Text("Notifications are disabled. Enable them in System Settings to get alerted when Claude is waiting for your input.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Allow notifications to get alerted when Claude is waiting for your input, even when the app is in the background.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      // Buttons
      HStack(spacing: 12) {
        Button("Don't Ask Again") {
          notificationService.dismissPromptPermanently()
          onDismiss()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)

        Spacer()

        if notificationService.authorizationDenied {
          Button("Open System Settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            notificationService.dismissPromptTemporarily()
            onDismiss()
          }
          .buttonStyle(.borderedProminent)
        } else {
          Button("Enable Notifications") {
            notificationService.requestPermission()
            onDismiss()
          }
          .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(16)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
  }
}

#Preview("Not Determined") {
  NotificationPermissionPromptView {
    print("Dismissed")
  }
  .frame(width: 400)
  .padding()
  .background(.black.opacity(0.3))
}
