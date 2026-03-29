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
import GhosttyEmbed

/// SwiftUI wrapper for a Ghostty terminal running a plain login shell.
/// No session monitoring, no session registration, no auto-close.
struct GhosttyPlainTerminalView: NSViewRepresentable {
  let workingDirectory: String
  let isSelected: Bool
  let onAction: (TerminalAction) -> Void
  let existingHostView: GhosttyHostView?
  let onHostViewCreated: ((GhosttyHostView) -> Void)?
  @Environment(\.colorScheme) private var colorScheme

  func makeNSView(context: Context) -> GhosttyHostView {
    if let existing = existingHostView { return existing }

    let hostView = GhosttyHostView()
    let launch = TerminalEnvironment.plainShellArgs(currentDirectory: workingDirectory)

    hostView.setupSurface(launch: launch, workingDirectory: workingDirectory, onAction: onAction)

    if isSelected { hostView.pendingFocus = true }
    onHostViewCreated?(hostView)
    return hostView
  }

  func updateNSView(_ nsView: GhosttyHostView, context: Context) {
    nsView.onAction = onAction

    if context.coordinator.lastColorScheme != colorScheme {
      context.coordinator.lastColorScheme = colorScheme
      GhosttyEmbedApp.shared.applyAppearance(isDark: colorScheme == .dark)
    }

    if isSelected {
      if nsView.window != nil {
        DispatchQueue.main.async {
          guard let surfaceView = nsView.surfaceViewIfReady, nsView.window != nil else { return }
          let fr = nsView.window?.firstResponder as? NSView
          if fr == nil || !(fr!.isDescendant(of: surfaceView)) {
            nsView.makeFocused()
          }
        }
      } else {
        nsView.pendingFocus = true
      }
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }
  class Coordinator { var lastColorScheme: ColorScheme = .dark }
}
