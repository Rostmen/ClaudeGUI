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

import Foundation

/// Manages detection and installation of the Claude Code hook script
@MainActor
protocol HookSetup: AnyObject {
  /// True when the hook script exists and is registered in ~/.claude/settings.json
  var hooksInstalled: Bool { get }

  /// True when the hook installation prompt should be shown to the user
  var shouldShowPrompt: Bool { get }

  /// Re-check the installation status on disk
  func checkInstallationStatus()

  /// Begin tracking a session to detect whether hook events arrive
  func trackSession(_ sessionId: String)

  /// Stop tracking a session (terminal closed or session deactivated)
  func untrackSession(_ sessionId: String)

  /// Called when a hook event is received for a session — suppresses the install prompt
  func receivedHookEvent(for sessionId: String)

  /// Hide the prompt until next app launch
  func dismissPromptTemporarily()

  /// Hide the prompt permanently (stored in UserDefaults)
  func dismissPromptPermanently()

  /// Copy the hook script and register it in ~/.claude/settings.json
  func installHooks() async -> Result<Void, HookInstallationError>

  /// Remove the hook script and unregister it from ~/.claude/settings.json
  func uninstallHooks() async -> Result<Void, HookInstallationError>
}

// MARK: - Conformance

extension HookInstallationService: HookSetup {}
