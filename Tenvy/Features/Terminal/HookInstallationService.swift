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

// MARK: - Claude Settings Schema

/// A group of hooks registered for one event type in ~/.claude/settings.json
struct ClaudeHookGroup: Codable, Equatable {
  var hooks: [ClaudeHookCommand]
}

/// An individual hook command entry
struct ClaudeHookCommand: Codable, Equatable {
  let type: String
  let command: String
}

/// Service for managing hook installation
@MainActor
@Observable
final class HookInstallationService {

  /// Whether hooks are currently installed
  private(set) var hooksInstalled: Bool = false

  /// Whether we should show the installation prompt
  private(set) var shouldShowPrompt: Bool = false

  /// Session IDs we're tracking for hook events
  private var trackedSessions: Set<String> = []

  /// Timer for checking if hooks are responding
  private var detectionTimer: Timer?

  /// Sessions that have been active but received no hook events
  private var sessionsWithoutHooks: Set<String> = []

  /// Path to the hook script
  private let hookScriptPath: URL

  /// Path to Claude settings
  private let claudeSettingsPath: URL

  /// Path to bundled hooks directory
  private var bundledHooksPath: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("Hooks")
  }

  init() {
    let claudeDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude")
    hookScriptPath = claudeDir
      .appendingPathComponent("hooks")
      .appendingPathComponent("chat-sessions-hook.sh")
    claudeSettingsPath = claudeDir.appendingPathComponent("settings.json")

    // Auto-install or upgrade hooks at startup
    ensureHooksInstalled()
  }

  /// Ensure hooks are installed and up-to-date.
  /// Installs if missing, upgrades if the script lacks `TENVY_SESSION_ID` support.
  func checkInstallationStatus() {
    let scriptExists = FileManager.default.fileExists(atPath: hookScriptPath.path)
    let hooks = loadHooks()
    let settingsConfigured = hooks["Stop"]?
      .flatMap(\.hooks)
      .contains { $0.command.contains("chat-sessions-hook.sh") } ?? false
    hooksInstalled = scriptExists && settingsConfigured
  }

  /// Auto-install or upgrade hooks. Called once at init.
  private func ensureHooksInstalled() {
    let scriptExists = FileManager.default.fileExists(atPath: hookScriptPath.path)
    let hooks = loadHooks()
    let settingsConfigured = hooks["Stop"]?
      .flatMap(\.hooks)
      .contains { $0.command.contains("chat-sessions-hook.sh") } ?? false

    // Check if installed script has terminal_id support
    var scriptUpToDate = false
    if scriptExists, let content = try? String(contentsOf: hookScriptPath, encoding: .utf8) {
      scriptUpToDate = content.contains("TENVY_SESSION_ID")
    }

    let needsInstall = !scriptExists || !settingsConfigured || !scriptUpToDate
    if needsInstall {
      Task {
        let result = await installHooks()
        if case .failure(let error) = result {
          print("HookInstallationService: Failed to install hooks: \(error)")
        }
      }
    } else {
      hooksInstalled = true
    }
  }

  /// Start tracking a session for hook events
  func trackSession(_ sessionId: String) {
    guard !hooksInstalled else { return }
    guard !AppSettings.shared.hookPromptDismissed else { return }

    trackedSessions.insert(sessionId)

    // Start detection timer if not running
    if detectionTimer == nil {
      detectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
        Task { @MainActor in
          self?.checkForMissingHookEvents()
        }
      }
    }
  }

  /// Stop tracking a session
  func untrackSession(_ sessionId: String) {
    trackedSessions.remove(sessionId)
    sessionsWithoutHooks.remove(sessionId)
  }

  /// Called when a hook event is received for a session
  func receivedHookEvent(for sessionId: String) {
    trackedSessions.remove(sessionId)
    sessionsWithoutHooks.remove(sessionId)

    // If we receive any hook event, hooks are working
    if !hooksInstalled {
      hooksInstalled = true
      shouldShowPrompt = false
    }
  }

  /// Check if tracked sessions have received hook events
  private func checkForMissingHookEvents() {
    detectionTimer = nil

    // Sessions still in trackedSessions haven't received hook events
    if !trackedSessions.isEmpty && !hooksInstalled && !AppSettings.shared.hookPromptDismissed {
      sessionsWithoutHooks = trackedSessions
      shouldShowPrompt = true
    }
  }

  /// Dismiss the prompt temporarily (will show again next launch)
  func dismissPromptTemporarily() {
    shouldShowPrompt = false
    trackedSessions.removeAll()
  }

  /// Dismiss the prompt permanently
  func dismissPromptPermanently() {
    shouldShowPrompt = false
    trackedSessions.removeAll()
    AppSettings.shared.hookPromptDismissed = true
  }

  /// Install hooks
  func installHooks() async -> Result<Void, HookInstallationError> {
    let fileManager = FileManager.default

    // Create hooks directory
    let hooksDir = hookScriptPath.deletingLastPathComponent()
    do {
      try fileManager.createDirectory(at: hooksDir, withIntermediateDirectories: true)
    } catch {
      return .failure(.directoryCreationFailed(error.localizedDescription))
    }

    // Copy hook script from bundle or create it
    if let bundledScript = Bundle.main.url(forResource: "chat-sessions-hook", withExtension: "sh", subdirectory: "Hooks") {
      do {
        if fileManager.fileExists(atPath: hookScriptPath.path) {
          try fileManager.removeItem(at: hookScriptPath)
        }
        try fileManager.copyItem(at: bundledScript, to: hookScriptPath)
      } catch {
        return .failure(.scriptCopyFailed(error.localizedDescription))
      }
    } else {
      // Create script inline if bundle resource not available
      let scriptContent = createHookScript()
      do {
        try scriptContent.write(to: hookScriptPath, atomically: true, encoding: .utf8)
      } catch {
        return .failure(.scriptCopyFailed(error.localizedDescription))
      }
    }

    // Make script executable
    do {
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath.path)
    } catch {
      return .failure(.permissionFailed(error.localizedDescription))
    }

    // Update Claude settings
    let settingsResult = updateClaudeSettings()
    if case .failure(let error) = settingsResult {
      return .failure(error)
    }

    // Update status
    checkInstallationStatus()
    shouldShowPrompt = false

    return .success(())
  }

  /// Uninstall hooks
  func uninstallHooks() async -> Result<Void, HookInstallationError> {
    let fileManager = FileManager.default

    // Remove hook script
    if fileManager.fileExists(atPath: hookScriptPath.path) {
      do {
        try fileManager.removeItem(at: hookScriptPath)
      } catch {
        return .failure(.scriptRemovalFailed(error.localizedDescription))
      }
    }

    // Remove hooks from Claude settings
    let settingsResult = removeHooksFromSettings()
    if case .failure(let error) = settingsResult {
      return .failure(error)
    }

    // Update status
    checkInstallationStatus()

    return .success(())
  }

  /// Remove our hooks from Claude settings
  private func removeHooksFromSettings() -> Result<Void, HookInstallationError> {
    var hooks = loadHooks()
    let hookEvents = Self.managedHookEvents

    for event in hookEvents {
      guard var groups = hooks[event] else { continue }
      // Remove commands that point to our script from each group
      groups = groups.compactMap { group -> ClaudeHookGroup? in
        let filtered = group.hooks.filter { !$0.command.contains("chat-sessions-hook.sh") }
        return filtered.isEmpty ? nil : ClaudeHookGroup(hooks: filtered)
      }
      if groups.isEmpty {
        hooks.removeValue(forKey: event)
      } else {
        hooks[event] = groups
      }
    }

    return saveHooks(hooks)
  }

  /// Update Claude settings to include our hooks
  private func updateClaudeSettings() -> Result<Void, HookInstallationError> {
    var hooks = loadHooks()
    let hookCommand = "~/.claude/hooks/chat-sessions-hook.sh"

    for event in Self.managedHookEvents {
      var groups = hooks[event, default: []]
      let alreadyRegistered = groups.flatMap(\.hooks).contains {
        $0.command.contains("chat-sessions-hook.sh")
      }
      if !alreadyRegistered {
        groups.append(ClaudeHookGroup(hooks: [ClaudeHookCommand(type: "command", command: hookCommand)]))
        hooks[event] = groups
      }
    }

    return saveHooks(hooks)
  }

  // MARK: - Settings Helpers

  private static let managedHookEvents = [
    "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop",
    "SessionStart", "SessionEnd", "Notification", "PermissionRequest"
  ]

  /// Load the hooks subtree from settings.json, typed as Codable structs.
  /// Returns an empty dict if the file is missing or has no hooks key.
  private func loadHooks() -> [String: [ClaudeHookGroup]] {
    guard let data = try? Data(contentsOf: claudeSettingsPath),
          let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hooksRaw = raw["hooks"],
          let hooksData = try? JSONSerialization.data(withJSONObject: hooksRaw),
          let decoded = try? JSONDecoder().decode([String: [ClaudeHookGroup]].self, from: hooksData)
    else { return [:] }
    return decoded
  }

  /// Write a hooks dict back into settings.json, preserving all other top-level keys.
  private func saveHooks(_ hooks: [String: [ClaudeHookGroup]]) -> Result<Void, HookInstallationError> {
    // Read the full raw settings (or start empty)
    var raw: [String: Any]
    if let data = try? Data(contentsOf: claudeSettingsPath),
       let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      raw = existing
    } else {
      raw = [:]
    }

    // Encode our typed hooks back to a JSONSerialization-compatible object
    do {
      let hooksData = try JSONEncoder().encode(hooks)
      let hooksObj = try JSONSerialization.jsonObject(with: hooksData)
      raw["hooks"] = hooksObj
      let output = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
      try output.write(to: claudeSettingsPath)
      return .success(())
    } catch {
      return .failure(.settingsUpdateFailed(error.localizedDescription))
    }
  }

  /// Create hook script content
  private func createHookScript() -> String {
    """
    #!/bin/bash
    # Tenvy hook script - receives Claude Code events and writes to events file

    EVENTS_FILE="${HOME}/.claude/chat-sessions-events.jsonl"

    # Read input from stdin
    INPUT=$(cat)

    # Extract fields from input JSON
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
    HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
    CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
    NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')
    # Terminal ID from Tenvy — enables reliable session ID mapping
    TERMINAL_ID="${TENVY_SESSION_ID:-}"

    # Skip if no session ID
    if [ -z "$SESSION_ID" ]; then
      exit 0
    fi

    # Map hook events to states
    case "$HOOK_EVENT" in
      "UserPromptSubmit")
        STATE="processing"
        ;;
      "PreToolUse")
        STATE="thinking"
        ;;
      "PostToolUse")
        STATE="thinking"
        ;;
      "Stop")
        STATE="waiting"
        ;;
      "PermissionRequest")
        STATE="waitingPermission"
        ;;
      "Notification")
        # Notification fires for multiple types — only treat permission_prompt as permission needed
        if [ "$NOTIFICATION_TYPE" = "permission_prompt" ]; then
          STATE="waitingPermission"
        elif [ "$NOTIFICATION_TYPE" = "idle_prompt" ]; then
          STATE="waiting"
        else
          # auth_success, elicitation_dialog, etc — not a state change we track
          exit 0
        fi
        ;;
      "SessionStart")
        STATE="started"
        ;;
      "SessionEnd")
        STATE="ended"
        ;;
      *)
        STATE="unknown"
        ;;
    esac

    # Build JSON output (compact single-line with -c flag for JSONL format)
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    OUTPUT=$(jq -cn \\
      --arg sid "$SESSION_ID" \\
      --arg evt "$HOOK_EVENT" \\
      --arg st "$STATE" \\
      --arg cwd "$CWD" \\
      --arg tool "$TOOL_NAME" \\
      --arg ts "$TIMESTAMP" \\
      --arg tid "$TERMINAL_ID" \\
      '{session_id: $sid, event: $evt, state: $st, cwd: $cwd, tool: (if $tool == "" then null else $tool end), timestamp: $ts, terminal_id: (if $tid == "" then null else $tid end)}')

    # Append to events file
    echo "$OUTPUT" >> "$EVENTS_FILE"
    """
  }
}

/// Errors that can occur during hook installation/uninstallation
enum HookInstallationError: Error, LocalizedError {
  case directoryCreationFailed(String)
  case scriptCopyFailed(String)
  case scriptRemovalFailed(String)
  case permissionFailed(String)
  case settingsUpdateFailed(String)

  var errorDescription: String? {
    switch self {
    case .directoryCreationFailed(let msg):
      return "Failed to create hooks directory: \(msg)"
    case .scriptCopyFailed(let msg):
      return "Failed to copy hook script: \(msg)"
    case .scriptRemovalFailed(let msg):
      return "Failed to remove hook script: \(msg)"
    case .permissionFailed(let msg):
      return "Failed to set script permissions: \(msg)"
    case .settingsUpdateFailed(let msg):
      return "Failed to update Claude settings: \(msg)"
    }
  }
}
