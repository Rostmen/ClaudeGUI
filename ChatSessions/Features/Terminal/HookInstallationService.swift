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

/// Service for managing hook installation
@MainActor
@Observable
final class HookInstallationService {
  static let shared = HookInstallationService()

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

  private init() {
    let claudeDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude")
    hookScriptPath = claudeDir
      .appendingPathComponent("hooks")
      .appendingPathComponent("chat-sessions-hook.sh")
    claudeSettingsPath = claudeDir.appendingPathComponent("settings.json")

    // Check initial installation status
    checkInstallationStatus()
  }

  /// Check if hooks are installed
  func checkInstallationStatus() {
    let fileManager = FileManager.default

    // Check if hook script exists
    let scriptExists = fileManager.fileExists(atPath: hookScriptPath.path)

    // Check if settings have our hooks configured
    var settingsConfigured = false
    if let data = try? Data(contentsOf: claudeSettingsPath),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let hooks = json["hooks"] as? [String: Any] {
      // Check if Stop hook is configured with our script
      if let stopHooks = hooks["Stop"] as? [[String: Any]] {
        for hookGroup in stopHooks {
          if let innerHooks = hookGroup["hooks"] as? [[String: Any]] {
            for hook in innerHooks {
              if let command = hook["command"] as? String,
                 command.contains("chat-sessions-hook.sh") {
                settingsConfigured = true
                break
              }
            }
          }
        }
      }
    }

    hooksInstalled = scriptExists && settingsConfigured
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
    let fileManager = FileManager.default

    // Read existing settings
    guard fileManager.fileExists(atPath: claudeSettingsPath.path),
          let data = try? Data(contentsOf: claudeSettingsPath),
          var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      // No settings file or invalid - nothing to remove
      return .success(())
    }

    // Get hooks section
    guard var hooks = settings["hooks"] as? [String: Any] else {
      // No hooks section - nothing to remove
      return .success(())
    }

    // Hook events we registered
    let hookEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionStart", "SessionEnd", "Notification"]

    for event in hookEvents {
      guard var eventHooks = hooks[event] as? [[String: Any]] else {
        continue
      }

      // Filter out our hook
      eventHooks = eventHooks.filter { hookGroup in
        if let innerHooks = hookGroup["hooks"] as? [[String: Any]] {
          // Keep hook group if none of its hooks are ours
          return !innerHooks.contains { hook in
            if let command = hook["command"] as? String {
              return command.contains("chat-sessions-hook.sh")
            }
            return false
          }
        }
        return true
      }

      if eventHooks.isEmpty {
        hooks.removeValue(forKey: event)
      } else {
        hooks[event] = eventHooks
      }
    }

    settings["hooks"] = hooks

    // Write settings back
    do {
      let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: claudeSettingsPath)
    } catch {
      return .failure(.settingsUpdateFailed(error.localizedDescription))
    }

    return .success(())
  }

  /// Update Claude settings to include our hooks
  private func updateClaudeSettings() -> Result<Void, HookInstallationError> {
    let fileManager = FileManager.default
    var settings: [String: Any] = [:]

    // Read existing settings if present
    if fileManager.fileExists(atPath: claudeSettingsPath.path),
       let data = try? Data(contentsOf: claudeSettingsPath),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      settings = json
    }

    // Get or create hooks section
    var hooks = settings["hooks"] as? [String: Any] ?? [:]

    // Hook events we need to register
    let hookEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionStart", "SessionEnd"]
    let hookCommand = "~/.claude/hooks/chat-sessions-hook.sh"

    for event in hookEvents {
      var eventHooks = hooks[event] as? [[String: Any]] ?? []

      // Check if our hook is already registered
      var alreadyRegistered = false
      for hookGroup in eventHooks {
        if let innerHooks = hookGroup["hooks"] as? [[String: Any]] {
          for hook in innerHooks {
            if let command = hook["command"] as? String,
               command.contains("chat-sessions-hook.sh") {
              alreadyRegistered = true
              break
            }
          }
        }
      }

      // Add our hook if not registered
      if !alreadyRegistered {
        let newHook: [String: Any] = [
          "hooks": [
            ["type": "command", "command": hookCommand]
          ]
        ]
        eventHooks.append(newHook)
        hooks[event] = eventHooks
      }
    }

    settings["hooks"] = hooks

    // Write settings back
    do {
      let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: claudeSettingsPath)
    } catch {
      return .failure(.settingsUpdateFailed(error.localizedDescription))
    }

    return .success(())
  }

  /// Create hook script content
  private func createHookScript() -> String {
    """
    #!/bin/bash
    # ChatSessions hook script - receives Claude Code events and writes to events file

    EVENTS_FILE="${HOME}/.claude/chat-sessions-events.jsonl"

    # Read input from stdin
    INPUT=$(cat)

    # Extract fields from input JSON
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
    HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
    CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

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

    if [ -n "$TOOL_NAME" ]; then
      OUTPUT=$(jq -cn \\
        --arg sid "$SESSION_ID" \\
        --arg evt "$HOOK_EVENT" \\
        --arg st "$STATE" \\
        --arg cwd "$CWD" \\
        --arg tool "$TOOL_NAME" \\
        --arg ts "$TIMESTAMP" \\
        '{session_id: $sid, event: $evt, state: $st, cwd: $cwd, tool: $tool, timestamp: $ts}')
    else
      OUTPUT=$(jq -cn \\
        --arg sid "$SESSION_ID" \\
        --arg evt "$HOOK_EVENT" \\
        --arg st "$STATE" \\
        --arg cwd "$CWD" \\
        --arg ts "$TIMESTAMP" \\
        '{session_id: $sid, event: $evt, state: $st, cwd: $cwd, timestamp: $ts}')
    fi

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
