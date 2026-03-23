# Tenvy

macOS app for managing and resuming Claude Code CLI sessions with a native transparent UI.

> **Full Documentation**: See [FEATURES.md](./FEATURES.md) for comprehensive feature documentation, architecture details, and implementation specifics.

## Quick Overview

- **Session Management**: Browse, resume, rename, and delete Claude Code sessions
- **Embedded Terminal**: SwiftTerm-based terminal with CPU-based state monitoring
- **Multi-Window Support**: Each session runs in isolated window/tab with single process
- **Git Changes**: Modified files tree with syntax-highlighted diffs
- **Notifications**: macOS notifications for waiting/permission states via Claude Code hooks
- **Glass UI**: Transparent window with dark overlay

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
│   │   ├── SessionManager.swift    # Discovery & FSEvents monitoring
│   │   ├── SessionListView.swift   # Session list with local selection
│   │   └── SessionRowView.swift    # Session row with status dot
│   ├── Terminal/                   # Terminal & process management
│   │   ├── SessionRuntimeState.swift  # Per-session runtime info (@Observable)
│   │   ├── ProcessManager.swift    # Process tracking & cleanup
│   │   ├── TerminalView.swift      # SwiftTerm wrapper + state monitoring
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
│   │   ├── AppSettings.swift       # User preferences (UserDefaults)
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
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator |
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
- `exec` replaces the shell with claude at the same PID — SwiftTerm process tracking is unaffected
- `LANG=en_US.UTF-8` is set if missing (GUI apps launched by launchd don't inherit it)
- Custom environment variables can be added in **Settings → Environment Variables** — stored in UserDefaults, applied after `~/.zshrc`

### Process Cleanup

Shell PID (not Claude PID) is used for termination:
- Killing shell terminates entire process tree
- Signal handlers: SIGTERM, SIGINT, SIGHUP
- Fallback: `atexit` handler

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
