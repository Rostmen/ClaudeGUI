---
name: Appearance mode and Claude theme sync
description: Light/Dark/System setting, ClaudeThemeSync, auto-restart idle sessions, Ghostty backend details
type: project
---

Tenvy has a Light/Dark/System appearance setting (Settings → Appearance), stored as `AppSettings.shared.appearanceMode` (`AppearanceMode` enum in `AppSettings.swift`).

**Why:** Users need readable terminal colors in both light and dark environments; Claude CLI has its own theme setting that must match.

**How to apply:** When working on appearance, terminal colors, or Claude theme sync, these are the key pieces:

- `ClaudeThemeSync.apply(_:)` — writes `"theme": "dark"|"light"` to `~/.claude.json`; called from `AppSettings.appearanceMode.didSet` and on app init
- `AppModel.restartWaitingSessions()` — called via `Notification.Name.appearanceModeDidChange`; restarts sessions with `hookState == .waiting`; skips `processing`/`thinking`/`waitingPermission`
- All three window types apply `preferredColorScheme`: main window (`ContentView`), Settings scene (`TenvyApp`), Release Notes `NSWindow` (uses `NSAppearance`)
- `ClaudeTerminalColors.darkPalette` / `.lightPalette` in `ClaudeTheme.swift` — SwiftTerm UInt16 values use `byte × 257` scaling
- Ghostty appearance: `GhosttyEmbedApp.shared.applyAppearance(isDark:)` rewrites temp config at `NSTemporaryDirectory()/tenvy-ghostty.conf` and calls `reloadConfig()`

**Ghostty terminal backend:** Ghostty launches Claude via a temp shell script (`NSTemporaryDirectory()/tenvy-UUID.sh`) run as `zsh -l /tmp/tenvy-UUID.sh` so `~/.zprofile` is sourced. Script deleted in `GhosttyHostView.deinit`. This is the same login-shell approach SwiftTerm uses.
