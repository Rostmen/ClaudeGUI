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
import GRDB

/// Terminal view for a Claude Code session.
/// Launches the Claude CLI, monitors the process, and provides a session-specific context menu.
struct ClaudeSessionTerminalView: NSViewRepresentable {
  let session: ClaudeSession?
  let isSelected: Bool
  var forkSourceSessionId: String? = nil
  var initScript: String? = nil
  let onAction: (TerminalAction) -> Void
  let existingHostView: GhosttyHostView?
  let onHostViewCreated: ((GhosttyHostView) -> Void)?
  @Environment(\.colorScheme) private var colorScheme

  func makeNSView(context: Context) -> GhosttyHostView {
    if let existing = existingHostView { return existing }

    let hostView = GhosttyHostView()
    let workingDirectory = session?.workingDirectory ?? NSHomeDirectory()

    let claudePath = ClaudePathResolver.findClaudePath()
    var args: [String] = []
    if let forkId = forkSourceSessionId {
      args = ["--resume", forkId, "--fork-session"]
    } else if let session = session, !session.isNewSession {
      args = ["--resume", session.id]
    }

    // Apply per-session permission settings as CLI flags and record the launch hash.
    //
    // CLI flags are ADDITIVE — they can't remove permissions already granted by
    // ~/.claude/settings.json or project settings. To handle removals:
    // - Compare per-session allow list against inherited (global+project) allow list
    // - Tools removed by the user → pass as --disallowedTools (deny overrides allow)
    // - Tools added by the user → pass as --allowedTools
    // - Explicit deny list → also passed as --disallowedTools
    if let terminalId = session?.terminalId,
       let record = try? AppDatabase.shared.databaseReader.read({ db in
         try SessionRecord.fetchOne(db, key: terminalId)
       }),
       let permSettings = record.decodedPermissionSettings {
      // Store the hash of what we're launching with so the Inspector can detect changes
      let newHash = permSettings.contentHash
      if record.launchedPermissionsHash != newHash {
        try? AppDatabase.shared.databaseWriter.write { db in
          if var rec = try SessionRecord.fetchOne(db, key: terminalId) {
            rec.launchedPermissionsHash = newHash
            try rec.update(db)
          }
        }
      }

      args.append(contentsOf: ["--permission-mode", permSettings.permissionMode.rawValue])

      // Compute what was inherited so we can detect removals
      let inherited = ClaudeSettingsService.mergeForNewSession(
        projectPath: session?.projectPath ?? ""
      )

      // Tools the user explicitly allows (pass as --allowedTools)
      if !permSettings.permissions.allow.isEmpty {
        args.append("--allowedTools")
        args.append(permSettings.permissions.allow.joined(separator: " "))
      }

      // Tools to deny: explicit deny list + tools removed from inherited allow list.
      // Deny rules override allow rules at any scope, so this effectively revokes
      // permissions that global/project settings would otherwise grant.
      let removedFromAllow = Set(inherited.permissions.allow)
        .subtracting(permSettings.permissions.allow)
      let allDenied = Set(permSettings.permissions.deny).union(removedFromAllow)
      if !allDenied.isEmpty {
        args.append("--disallowedTools")
        args.append(allDenied.joined(separator: " "))
      }
    }

    let launch = TerminalEnvironment.shellArgs(executable: claudePath, args: args, currentDirectory: workingDirectory, initScript: initScript)

    hostView.setupSurface(launch: launch, workingDirectory: workingDirectory, terminalId: session?.terminalId, onAction: onAction)
    hostView.contextMenuProvider = { [weak hostView] in
      guard let hostView else { return NSMenu() }
      let target = SessionMenuTarget(onAction: hostView.onAction)
      hostView.menuTarget = target
      return Self.buildMenu(surfaceView: hostView.surfaceViewIfReady, target: target)
    }
    hostView.setupMonitoring(sessionId: session?.id, isNewSession: session?.isNewSession ?? false)

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

    let wasSelected = context.coordinator.wasSelected
    context.coordinator.wasSelected = isSelected

    // Only grab focus on the transition from deselected → selected,
    // not on every re-render while selected (which steals focus from dialogs/dropdowns).
    if isSelected && !wasSelected {
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
  class Coordinator {
    var lastColorScheme: ColorScheme = .dark
    var wasSelected: Bool = false
  }

  // MARK: - Context Menu

  private static func buildMenu(surfaceView: NSView?, target: SessionMenuTarget) -> NSMenu {
    let menu = NSMenu()

    if let surfaceView {
      menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "").target = surfaceView
    }
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "").target = surfaceView

    menu.addItem(.separator())
    for (title, dir, icon) in splitItems {
      let item = menu.addItem(withTitle: title, action: #selector(SessionMenuTarget.split(_:)), keyEquivalent: "")
      item.target = target
      item.representedObject = dir
      item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
    }

    menu.addItem(.separator())
    menu.addItem(withTitle: "Rename Session...", action: #selector(SessionMenuTarget.rename), keyEquivalent: "").target = target
    menu.addItem(withTitle: "Close Session", action: #selector(SessionMenuTarget.close), keyEquivalent: "").target = target

    return menu
  }

  private static let splitItems: [(String, SplitDirection, String)] = [
    ("Split Right", .right, "rectangle.righthalf.inset.filled"),
    ("Split Left", .left, "rectangle.leadinghalf.inset.filled"),
    ("Split Down", .down, "rectangle.bottomhalf.inset.filled"),
    ("Split Up", .up, "rectangle.tophalf.inset.filled"),
  ]
}

/// Action target for Claude session context menu.
/// Captures the action handler directly — no host reference needed.
private class SessionMenuTarget: NSObject {
  let onAction: (TerminalAction) -> Void

  init(onAction: @escaping (TerminalAction) -> Void) {
    self.onAction = onAction
  }

  @objc func split(_ sender: NSMenuItem) {
    guard let direction = sender.representedObject as? SplitDirection else { return }
    onAction(.splitRequested(direction: direction))
  }

  @objc func rename(_ sender: Any) { onAction(.renameRequested) }
  @objc func close(_ sender: Any) { onAction(.closeRequested) }
}
