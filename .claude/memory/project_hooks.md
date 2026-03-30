---
name: Claude Code hooks implementation
description: How Tenvy uses Claude Code hooks to track session state and trigger notifications
type: project
---

Hook script at `Hooks/chat-sessions-hook.sh` writes events to `~/.claude/chat-sessions-events.jsonl`.
Inline version in `HookInstallationService.swift` (`createHookScript()`).

**Registered events**: `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SessionStart`, `SessionEnd`, `Notification`, `PermissionRequest`

**State mapping**:
- `PermissionRequest` → `waitingPermission` (correct hook for actual permission dialogs)
- `Notification` + `notification_type=permission_prompt` → `waitingPermission`
- `Notification` + `notification_type=idle_prompt` → `waiting`
- `Notification` + other types (auth_success, elicitation_dialog) → ignored (exit 0)
- `Stop` → `waiting`

**Key insight**: `Notification` is a generic event for ALL notification types — must check `notification_type` field. Using `Notification` alone for `waitingPermission` caused idle sessions to wrongly show as permission-needed.

**Permission responses** sent to terminal:
- Allow Once → `\r` (Enter — first option pre-selected)
- Allow Session → `\u{1B}[B` + `\r` (arrow down + Enter)

**How to apply:** When modifying hook events or states, keep both the inline script in `HookInstallationService.swift` AND `Hooks/chat-sessions-hook.sh` in sync.
