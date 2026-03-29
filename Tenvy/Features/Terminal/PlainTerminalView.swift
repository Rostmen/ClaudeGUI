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

/// Terminal view for a plain login shell.
/// No Claude CLI, no session monitoring, no auto-close.
/// Provides its own context menu with terminal-specific actions (reset, rename, close).
struct PlainTerminalView: NSViewRepresentable {
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
    hostView.contextMenuProvider = { [weak hostView] in
      guard let hostView else { return NSMenu() }
      let target = PlainTerminalMenuTarget(
        onAction: hostView.onAction,
        onReset: { [weak hostView] in hostView?.resetTerminal() }
      )
      hostView.menuTarget = target
      return Self.buildMenu(surfaceView: hostView.surfaceViewIfReady, target: target)
    }

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

  // MARK: - Context Menu

  private static func buildMenu(surfaceView: NSView?, target: PlainTerminalMenuTarget) -> NSMenu {
    let menu = NSMenu()

    if let surfaceView {
      menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "").target = surfaceView
    }
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "").target = surfaceView

    menu.addItem(.separator())
    for (title, dir, icon) in splitItems {
      let item = menu.addItem(withTitle: title, action: #selector(PlainTerminalMenuTarget.split(_:)), keyEquivalent: "")
      item.target = target
      item.representedObject = dir
      item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
    }

    menu.addItem(.separator())
    let resetItem = menu.addItem(withTitle: "Reset Terminal", action: #selector(PlainTerminalMenuTarget.reset), keyEquivalent: "")
    resetItem.target = target
    resetItem.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise", accessibilityDescription: nil)

    menu.addItem(withTitle: "Rename Terminal...", action: #selector(PlainTerminalMenuTarget.rename), keyEquivalent: "").target = target
    menu.addItem(withTitle: "Close Terminal", action: #selector(PlainTerminalMenuTarget.close), keyEquivalent: "").target = target

    return menu
  }

  private static let splitItems: [(String, SplitDirection, String)] = [
    ("Split Right", .right, "rectangle.righthalf.inset.filled"),
    ("Split Left", .left, "rectangle.leadinghalf.inset.filled"),
    ("Split Down", .down, "rectangle.bottomhalf.inset.filled"),
    ("Split Up", .up, "rectangle.tophalf.inset.filled"),
  ]
}

/// Action target for plain terminal context menu.
/// Captures the action handler and reset closure — no host reference needed.
private class PlainTerminalMenuTarget: NSObject {
  let onAction: (TerminalAction) -> Void
  let onReset: () -> Void

  init(onAction: @escaping (TerminalAction) -> Void, onReset: @escaping () -> Void) {
    self.onAction = onAction
    self.onReset = onReset
  }

  @objc func split(_ sender: NSMenuItem) {
    guard let direction = sender.representedObject as? SplitDirection else { return }
    onAction(.splitRequested(direction: direction))
  }

  @objc func reset(_ sender: Any) { onReset() }
  @objc func rename(_ sender: Any) { onAction(.renameRequested) }
  @objc func close(_ sender: Any) { onAction(.closeRequested) }
}
