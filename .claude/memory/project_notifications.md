---
name: macOS notifications implementation
description: How Tenvy implements macOS notifications — key decisions and gotchas
type: project
---

`NotificationService` (`Tenvy/App/NotificationService.swift`) — `@Observable`, `@MainActor`, singleton.

**Key implementation decisions**:
- Delegate must be set BEFORE `requestAuthorization` (otherwise delegate is ignored)
- `@Observable` is required — without it SwiftUI can't track `shouldShowPrompt` changes
- `willPresent`: suppress only when session is in the **key window**; show for background/other windows
- Actions must NOT use `.foreground` option — it causes macOS to create a new WindowGroup window before the delegate fires
- No Deny action — only Allow Once and Allow Session

**Dedup guard (`pendingNotifications`)**:
- On app focus, clear notification only for the **focused session window** (not all sessions)
- Clearing all sessions wipes the dedup guard for background sessions, causing re-notifications when those sessions fire new hook events
- `clearAllNotifications()` is for full reset only (hooks uninstalled, etc.)

**Permission response optimistic clear**:
- When user taps Allow Once / Allow Session in notification action, immediately set hookState to `.waiting`
- Hook events will confirm/update the actual state shortly after
- Prevents "Needs Permission" persisting in sidebar after user responds

**`markActivated()` resets hookState**:
- When a session terminal is (re)started, hookState and currentTool are cleared
- Prevents stale "Needs Permission" from a previous session run persisting on reopen

**In-app permission prompt** (`NotificationPermissionPromptView`): shown at bottom-right like the hook installation prompt. Uses `shouldShowPrompt` observable property.

**`NSUserNotificationAlertStyle = alert`** in Info.plist — makes notifications persistent (don't auto-dismiss).

**Dock badge**: counts sessions not visible in key window (not just "app inactive").

**How to apply:** If notification behavior breaks, check: delegate set before auth, @Observable present, no .foreground on actions, willPresent checks key window session, focus clear is per-session not all-sessions.
