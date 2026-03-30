---
name: Update checker and auto-update flow
description: How Tenvy checks for updates and installs them silently via Homebrew
type: project
---

`UpdateService` (`Tenvy/Features/Updates/UpdateService.swift`) — `@Observable`, `@MainActor`, singleton.

**Update check**: runs on every launch (no throttle). Fetches `https://api.github.com/repos/Rostmen/ClaudeGUI/releases/latest`, compares semver with `AppInfo.version`. Shows `UpdatePromptView` overlay (bottom-right) if newer.

**Install flow** (`performUpdate()`):
1. Sets `isUpdating = true` (bypasses quit/close confirmation dialogs)
2. Runs `brew install --cask --force rostmen/tenvy/tenvy` silently via `Process` (no Terminal window)
3. On success: opens `/Applications/Tenvy.app`, then `NSApplication.shared.terminate(nil)`
4. On failure: shows error message in prompt with brew exit code

**In-app states**: `UpdateState` enum — `.idle`, `.installing`, `.success`, `.failed(String)`

**`isUpdating` flag**: checked in `applicationShouldTerminate` and `windowShouldClose` — returns `.terminateNow`/`true` immediately so brew can quit the running app without confirmation dialogs.

**Release notes**: fetched from GitHub release body. Shown in a dark `NSWindow` (stored as `releaseNotesWindow` instance var on AppDelegate — must retain or crashes on close). Shown on first launch of each new version using `AppSettings.lastSeenVersion`.

**How to apply:** If update prompt shows but install fails, check brew path (`/opt/homebrew/bin/brew` or `/usr/local/bin/brew`). If app crashes on release notes close, ensure `releaseNotesWindow` is retained as instance var.
