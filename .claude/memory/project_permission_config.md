---
name: Permission Configuration
description: Two-level permission management (global + per-session) with shared PermissionEditorView, GRDB storage, CLI flag integration, and SHA-256 hash-based change detection
type: project
---

Two-level permission management for Claude Code sessions.

**Global**: Settings -> Claude Permissions section reads/writes `~/.claude/settings.json` via `ClaudeSettingsService`. Preserves other keys (hooks, plugins). Changes apply to new sessions.

**Per-session**: Stored as JSON in `SessionRecord.permissionSettings` (GRDB). Inherited from global + project on creation via `ClaudeSettingsService.mergeForNewSession()`. Editable in Inspector Panel. Changes saved to DB immediately.

**Launch**: `ClaudeSessionTerminalView.makeNSView()` reads from DB and passes `--permission-mode`, `--allowedTools`, `--disallowedTools` CLI flags. CLI flags are additive, so tools removed from the inherited allow list are automatically passed as `--disallowedTools` (deny overrides allow in Claude Code). Records launched-with state as SHA-256 hash in `SessionRecord.launchedPermissionsHash`.

**Change detection**: Uses SHA-256 hash (`ClaudePermissionSettings.contentHash` via CryptoKit, sorted-keys JSON encoding). Inspector compares `sessionPermissions.contentHash` against `launchedPermissionsHash` from DB. Restart button appears only when hashes differ; reverting changes hides it.

**Restart flow**: Confirmation dialog first. Then `ContentViewModel.restartSessionWithNewPermissions()` kills process, evicts GhosttyHostView cache, and assigns a new `ghosttyInstanceId` on `SessionRuntimeInfo`. The instance ID change updates `.id()` on the terminal view, forcing SwiftUI to destroy and recreate the NSViewRepresentable (triggering fresh `makeNSView`). Inspector re-reads hash from DB after restart.

**Shared UI**: `PermissionEditorView` takes `Binding<ClaudePermissionSettings>`. Used in both Settings (global, writes to file) and Inspector (per-session, writes to DB). Includes mode picker, preset toggles, allow/deny/ask rule lists, raw JSON editor sheet.

**Why:** User requested GUI for managing Claude Code permissions instead of hand-editing JSON files. Global settings manage `~/.claude/settings.json`; per-session stored in GRDB and applied via CLI flags at launch.

**How to apply:** When modifying permission-related code, keep the shared `PermissionEditorView` agnostic to its context (global vs per-session). The editor takes a binding; the caller handles persistence. CLI flags are additive — always compute denied tools by comparing against inherited permissions.
