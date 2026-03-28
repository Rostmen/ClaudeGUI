# Tenvy

macOS app for managing and resuming Claude Code CLI sessions with a native transparent UI.

> **Full Documentation**: See [FEATURES.md](./FEATURES.md) for comprehensive feature documentation, architecture details, and implementation specifics.

## Quick Overview

- **Session Management**: Browse, resume, rename, and delete Claude Code sessions
- **Embedded Terminal**: Ghostty terminal with CPU-based state monitoring
- **Split Panes**: Tree-based split layout (Ghostty-style) — splitting only divides the focused pane, not all panes
- **Multi-Window Support**: Each session runs in isolated window/tab with single process
- **Git Changes**: Modified files tree with syntax-highlighted diffs
- **Notifications**: macOS notifications for waiting/permission states via Claude Code hooks
- **Glass UI**: Transparent window with dark overlay
- **Appearance**: Light / Dark / System mode with live Claude CLI theme sync

## Architecture

```
Tenvy/
├── App/                            # App entry & shared state
│   ├── TenvyApp.swift              # App entry + AppDelegate + WindowAccessor
│   ├── AppState.swift              # Shared singleton (sessions, runtime, registry)
│   ├── ContentView.swift           # Main layout (UI only)
│   ├── ContentViewModel.swift      # Session selection & window coordination
│   ├── NotificationService.swift   # macOS notifications (UNUserNotificationCenter)
│   └── NotificationPermissionPromptView.swift  # In-app permission prompt
├── Features/
│   ├── Session/                    # Session management
│   │   ├── ClaudeSession.swift     # Session data model
│   │   ├── PaneSplitTree.swift     # Recursive binary tree for split pane layout
│   │   ├── SessionManager.swift    # Discovery & FSEvents monitoring
│   │   ├── SessionListView.swift   # Session list with local selection
│   │   └── SessionRowView.swift    # Session row with status dot
│   ├── Terminal/                   # Terminal & process management
│   │   ├── SessionRuntimeState.swift  # Per-session runtime info (@Observable)
│   │   ├── ProcessManager.swift    # Process tracking & cleanup
│   │   ├── TerminalView.swift      # Shared types: SplitDirection, SessionMonitorInfo, SessionStateMonitor
│   │   ├── GhosttyTerminalView.swift  # Ghostty terminal backend + GhosttyHostView + focus transfer
│   │   ├── PaneSplitView.swift     # Two-pane split view with draggable divider
│   │   ├── EmptyTerminalView.swift # Empty state placeholder
│   │   ├── ClaudePathResolver.swift   # Finds claude CLI binary
│   │   ├── TerminalEnvironment.swift  # Terminal env var configuration
│   │   ├── TerminalRegistry.swift  # Weak refs to terminals for sending input
│   │   ├── HookInstallationService.swift  # Claude Code hook setup
│   │   ├── HookInstallationPromptView.swift  # Hook install prompt UI
│   │   ├── HookEventService.swift  # Reads hook events file
│   │   └── ProcessTreeAnalyzer.swift  # Process tree analysis
│   ├── Git/                        # Git integration
│   │   ├── GitChangedFile.swift    # Git changed file model
│   │   ├── GitStatusService.swift  # Git status detection
│   │   ├── GitChangesService.swift # Git tree loading & diff fetching
│   │   ├── GitChangesView.swift    # Git changes tree view
│   │   ├── GitChangedFileTreeNode.swift  # Recursive tree node
│   │   ├── GitChangedFileRow.swift # Git file row
│   │   └── DiffView.swift          # Git diff viewer
│   ├── Settings/                   # Settings
│   │   ├── AppSettings.swift       # User preferences (UserDefaults) + AppearanceMode
│   │   ├── ClaudeThemeSync.swift   # Writes theme to ~/.claude.json on appearance change
│   │   └── SettingsView.swift      # App preferences view
│   └── Updates/                    # Update checker
│       ├── UpdateService.swift     # GitHub releases API + brew install
│       ├── UpdatePromptView.swift  # Bottom-right update prompt overlay
│       └── ReleaseNotesView.swift  # Release notes window on new version
├── Shared/                         # Shared components
│   ├── WindowSessionRegistry.swift # Window-session mapping
│   ├── SessionGroupingService.swift # Session grouping & filtering
│   ├── SidebarView.swift           # Tabbed sidebar
│   ├── SidebarTab.swift            # Sidebar tab enum
│   ├── SidebarTabBar.swift         # Tab bar picker
│   ├── SidebarTabButton.swift      # Individual tab button
│   ├── NoSessionSelectedView.swift # Empty state for changes tab
│   └── ClaudeTheme.swift           # Theme colors + ANSI palette
└── Resources/
    └── Assets.xcassets
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| [GhosttyEmbed](https://github.com/ghostty-org/ghostty) | Ghostty terminal backend |
| [gitdiff](https://github.com/tornikegomareli/gitdiff) | Diff rendering |

## Building

```bash
xcodebuild -scheme Tenvy -destination 'platform=macOS'
```

Or open `Tenvy.xcodeproj` in Xcode and press Cmd+R.

**Requirements**: macOS 26.2+, Xcode 17+

---

## Releasing

### Automated (GitHub Actions)

Push a version tag to trigger the full build → sign → notarize → DMG → GitHub Release pipeline:

```bash
git tag v1.2.3
git push origin v1.2.3
```

The workflow (`.github/workflows/release.yml`) runs on `macos-26`:
1. Selects latest stable Xcode (non-beta)
2. Installs Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain` — required on CI)
3. Imports `Developer ID Application` certificate from GitHub Secrets
4. Archives unsigned (`CODE_SIGNING_ALLOWED=NO`) — avoids xcodebuild cert validation issues
5. Signs manually with `codesign` — frameworks first, then app bundle with `--options runtime --timestamp`
6. Notarizes with `xcrun notarytool` and staples ticket
7. Packages as DMG with `create-dmg`
8. Creates GitHub Release with DMG attached

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE` | Base64-encoded `.p12` — export **Developer ID Application** cert+key from Keychain, then `base64 -i cert.p12 \| pbcopy`. Must include private key. Use `echo -n` when decoding. |
| `APPLE_CERTIFICATE_PASSWORD` | Password set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | Any random string (`openssl rand -base64 20`) |
| `APPLE_ID` | Apple ID email for notarization |
| `APPLE_APP_PASSWORD` | App-specific password from [appleid.apple.com](https://appleid.apple.com) → App-Specific Passwords |
| `APPLE_TEAM_ID` | 10-char team ID from [developer.apple.com/account](https://developer.apple.com/account) |

### Why not App Store?

The app spawns shell processes (`claude` CLI, `git`) and reads/writes `~/.claude/` — incompatible with App Sandbox. Distributed as a notarized direct download instead.

### Manual Release (local)

```bash
brew install create-dmg
./scripts/release.sh 1.2.3
```

---

## Critical Implementation Details

### Multi-Window Process Isolation

Each session has exactly ONE process. Prevention mechanisms:

1. **WindowSessionRegistry**: Maps window → session
2. **NSWindow.sessionId**: Associated object fallback
3. **AppState.activatedSessions**: Tracks active terminals
4. **Terminal render condition**: `windowConfigured && currentWindow?.sessionId == session.id`

### Session State Monitoring

CPU-based state detection:
- `> 25% CPU` → thinking (yellow)
- `< 3% CPU` → waiting (green)
- Rolling 3-sample average, 0.5s polling

### Claude Code Hooks

Hook events are written to `~/.claude/chat-sessions-events.jsonl` by `Hooks/chat-sessions-hook.sh`.

Registered events and their state mappings:

| Hook Event | `notification_type` | App State |
|-----------|---------------------|-----------|
| `UserPromptSubmit` | — | `processing` |
| `PreToolUse` / `PostToolUse` | — | `thinking` |
| `Stop` | — | `waiting` |
| `PermissionRequest` | — | `waitingPermission` |
| `Notification` | `permission_prompt` | `waitingPermission` |
| `Notification` | `idle_prompt` | `waiting` |
| `Notification` | other | ignored |
| `SessionStart` | — | `started` |
| `SessionEnd` | — | `ended` |

**Key**: `PermissionRequest` is the correct hook for actual permission dialogs. `Notification` is a generic event that fires for multiple types — always check `notification_type`.

### Notifications

- `NotificationService` uses `UNUserNotificationCenter` with `@Observable`
- `willPresent`: suppresses notification only when the session is in the **key window**; shows it for background windows
- On app focus: clears notification only for the **focused session window** (not all sessions) — prevents wiping dedup guard for background sessions
- Permission responses: `allowOnce` → Enter (`\r`), `allowSession` → ↓+Enter; optimistically clears `waitingPermission` hookState immediately
- `NSUserNotificationAlertStyle = alert` in Info.plist for persistent (non-disappearing) banners

### Terminal Environment

Claude is launched **through the user's login shell** to ensure `~/.zprofile` and `~/.zshrc` are sourced:

```
zsh -l -c '[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null; exec /path/to/claude [args]'
```

- `-l` sources `/etc/zprofile` and `~/.zprofile`
- `~/.zshrc` is sourced manually (not via `-i` which triggers `/etc/zshrc` terminal key-binding setup and causes errors without a TTY)
- `exec` replaces the shell with claude at the same PID — process tracking is unaffected
- `LANG=en_US.UTF-8` is set if missing (GUI apps launched by launchd don't inherit it)
- Custom environment variables can be added in **Settings → Environment Variables** — stored in UserDefaults, applied after `~/.zshrc`

### Process Cleanup

Shell PID (not Claude PID) is used for termination:
- Killing shell terminates entire process tree
- Signal handlers: SIGTERM, SIGINT, SIGHUP
- Fallback: `atexit` handler

### Appearance Mode & Claude Theme Sync

- `AppSettings.appearanceMode` stores `AppearanceMode` enum: `.system`, `.light`, `.dark`
- `preferredColorScheme` applied to all three window types: main (`ContentView`), Settings scene, Release Notes `NSWindow`
- On change: `ClaudeThemeSync.apply(_:)` writes `"theme": "dark"|"light"` to `~/.claude.json`; System mode resolves via `NSApp.effectiveAppearance`
- On change: `AppModel.restartWaitingSessions()` restarts sessions with `hookState == .waiting` so Claude CLI picks up the new theme immediately; sessions with `processing`, `thinking`, or `waitingPermission` are left alone
- Ghostty appearance: `GhosttyEmbedApp.shared.applyAppearance(isDark:)` rewrites the temp config and calls `reloadConfig()`
- `ContentView` observes `@Environment(\.colorScheme)` and re-syncs `ClaudeThemeSync` on system appearance change

### Split Panes (Ghostty-style)

- **Tree model**: `PaneSplitTree` — recursive binary tree (`leaf(ClaudeSession)` | `split(Split)`). Splitting a leaf replaces only that leaf with a split node; the rest of the tree is untouched.
- **`PaneSplitView`**: two-pane SwiftUI view using `GeometryReader + ZStack + offset` (NOT `NSSplitView`). Draggable divider updates `Split.ratio` via `ContentViewModel.updateSplitRatio(splitId:ratio:)`.
- **`PaneSplitTreeRenderer`** (private struct in `ContentView`): recursively renders the tree — `leaf` → `TerminalView`, `split` → `PaneSplitView` with two recursive renderers.
- **`selectedSession`** tracks the focused pane; `primarySession` tracks the window-registered session (the first pane).
- **Auto-close**: non-primary panes automatically close when their `claude` process exits (`.inactive` state).
- **`syncSplitSession()`**: like `syncNewSessionWithDiscoveredSession()` but for split panes — updates `isNewSession` leaves when Claude creates the real session file.

#### Ghostty Focus in Split Mode

Ghostty's `SurfaceView` defaults `focused = true`. This breaks `performKeyEquivalent` routing — if a non-selected pane's surface has `focused = true`, it intercepts Cmd+V (paste) and other key equivalents before the actually-focused pane.

**Fix**: in `GhosttyHostView.setup()`, call `_ = surfaceView.resignFirstResponder()` immediately after `addSubview(surfaceView)`. This resets `focused = false` on all new surfaces. Focus is granted only when `makeFocused()` is called (via `pendingFocus` + `viewDidMoveToWindow` for the selected pane).

- `GhosttyEmbedSurface.makeFocused()`: calls `resignFirstResponder()` (now a no-op since focused is already false) then `window.makeFirstResponder(surfaceView)` → `becomeFirstResponder()` → `focusDidChange(true)` → `ghostty_surface_set_focus(surface, true)`.
- `GhosttyHostView`: uses KVO on `window.firstResponder` to call `onFocusGained` → `ContentViewModel.handleFocusGained(for:)` → updates `selectedSession`.
- `pendingFocus: Bool` on `GhosttyHostView`: set in `makeNSView` when `isSelected = true`, consumed in `viewDidMoveToWindow` (reliable point where `window` is non-nil).
- **`viewDidMoveToWindow` defer**: `pendingFocus` calls `makeFocused()` via `DispatchQueue.main.async`, not synchronously. Ghostty's `SurfaceView.viewDidMoveToWindow` fires after the host view's, and resets internal focus state — deferring by one run loop tick ensures `makeFocused()` runs after all `viewDidMoveToWindow` callbacks complete.

#### GhosttyHostView Cache (process survival across split transitions)

SwiftUI destroys and recreates `NSViewRepresentable`-backed views when they move to a different structural position in the view tree (e.g. single-pane → split). This kills the Ghostty process. Fix: `ContentViewModel` holds a strong `[String: GhosttyHostView]` cache keyed by `session.terminalId`.

- `@ObservationIgnored private var ghosttyHostViews: [String: GhosttyHostView]` — strong refs, invisible to SwiftUI observation.
- `GhosttyTerminalView.makeNSView`: returns cached view if `existingHostView != nil`, skipping `setup()` (no new process).
- `onHostViewCreated` callback: fires in `makeNSView` for fresh views, allowing callers to populate the cache.
- Cache is evicted in `closeSplitPane(id:)` and `closeSplit()` before deactivating, so the Ghostty process terminates when the pane is explicitly closed.

### Ghostty Terminal Backend

- `GhosttyTerminalView` (NSViewRepresentable) is the sole terminal backend; used directly in `ContentView`
- Launches via a login-shell wrapper: writes a temp shell script to `NSTemporaryDirectory()`, runs `zsh -l /tmp/tenvy-UUID.sh` so `~/.zprofile` is sourced and PATH is correct; script deleted in `deinit`
- Resize: `GhosttyHostView.layout()` calls `surface.notifyResize(bounds.size)` → `surfaceView.sizeDidChange(_:)`
- Input: `GhosttyInputProxy` conforms to `TerminalInputSender`; restart is a no-op (Ghostty doesn't support programmatic restart)

### Update Checker

- `UpdateService` checks GitHub releases API on every launch, compares with `AppInfo.version`
- Shows `UpdatePromptView` overlay (bottom-right) when a newer version is available
- Update runs `brew install --cask --force rostmen/tenvy/tenvy` silently via `Process` (no Terminal window)
- In-app progress states: `idle → installing → success → failed`
- On success: opens `/Applications/Tenvy.app` then terminates current process
- `isUpdating: Bool` flag bypasses quit/close confirmation dialogs when brew sends terminate signal
- Release notes fetched from GitHub release body and shown in a dark `NSWindow` on first launch of a new version

---

## SwiftUI Coding Conventions

### One View Per File

Each SwiftUI view should have its own dedicated file with a `#Preview` macro.

**Exceptions**: tiny private helper views used only by the parent, tightly coupled views always used together.

**When to extract**: reusable across files, has own state/logic, would benefit from isolated preview, file > ~200 lines.

### Preview Guidelines

- Every public view file must have at least one `#Preview`
- Use named previews for multiple states: `#Preview("Selected State") { ... }`
- Include realistic sample data in previews

---

## Claude Code Workflow Rules

**Git commits and pushes:**
- **DO NOT** commit or push until the user explicitly verifies the changes are good
- Always wait for user approval before running `git commit` or `git push`

---

## Maintenance Notes

**IMPORTANT**: Keep documentation updated when making changes:

- Update [FEATURES.md](./FEATURES.md) for feature changes
- Update architecture diagram when adding/removing files
- Update dependencies when adding new packages
- Update hook event table when adding new hook events
