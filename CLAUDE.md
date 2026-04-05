# Tenvy

macOS app for managing and resuming Claude Code CLI sessions with a native transparent UI.

> **Full Documentation**: See [FEATURES.md](./FEATURES.md) for comprehensive feature documentation, architecture details, and implementation specifics.

## Quick Overview

- **Session Management**: Browse, resume, rename, and delete Claude Code sessions
- **Embedded Terminal**: Ghostty terminal with CPU-based state monitoring
- **Split Panes**: Tree-based split layout (Ghostty-style) — splitting only divides the focused pane, not all panes. Both splits and new session creation intercept to offer git worktree creation for parallel branch work
- **Multi-Window Support**: Each session runs in isolated window/tab with single process
- **Inspector Panel**: Collapsible right-side panel with branch switcher and path info (⌘⌥I)
- **Open in IDE**: Detects project type and installed IDEs, toolbar button to open in matched IDE
- **Git Changes**: Modified files tree with syntax-highlighted diffs
- **Notifications**: macOS notifications for waiting/permission states via Claude Code hooks
- **Glass UI**: Transparent window with dark overlay
- **Appearance**: Light / Dark / System mode with live Claude CLI theme sync

## Architecture

```
Tenvy/
├── App/                            # App entry & shared state
│   ├── TenvyApp.swift              # App entry + AppDelegate + WindowAccessor + DatabaseContext
│   ├── AppState.swift              # Shared singleton (sessions, runtime, registry)
│   ├── ContentView.swift           # Main layout (UI only, uses @Query for DB-backed state)
│   ├── ContentViewModel.swift      # Session selection & window coordination
│   ├── NotificationService.swift   # macOS notifications (UNUserNotificationCenter)
│   └── NotificationPermissionPromptView.swift  # In-app permission prompt
├── Features/
│   ├── Session/                    # Session management
│   │   ├── ClaudeSession.swift     # Session data model
│   │   ├── PaneSplitTree.swift     # Recursive binary tree for split pane layout
│   │   ├── SessionManager.swift    # Discovery & FSEvents monitoring
│   │   ├── SessionListView.swift   # Session list + SessionListAction enum
│   │   ├── SessionRowView.swift    # Session row with status dot + drag handle
│   │   └── DeleteSessionConfirmationView.swift  # Delete confirmation with worktree removal option
│   ├── Terminal/                   # Terminal & process management
│   │   ├── SessionRuntimeState.swift  # Per-session runtime info (@Observable)
│   │   ├── ProcessManager.swift    # Process tracking & cleanup
│   │   ├── TerminalView.swift      # Shared types: SplitDirection, SessionMonitorInfo, SessionStateMonitor
│   │   ├── TerminalAction.swift    # Action enum for terminal → ViewModel communication
│   │   ├── GhosttyHostView.swift   # Generic Ghostty NSView host (surface, focus, monitoring)
│   │   ├── GhosttyInputProxy.swift # Terminal input sender (TerminalInputSender)
│   │   ├── ClaudeSessionTerminalView.swift  # Claude session terminal (NSViewRepresentable)
│   │   ├── PlainTerminalView.swift # Plain shell terminal (NSViewRepresentable)
│   │   ├── PaneSplitView.swift     # Two-pane split view with draggable divider
│   │   ├── PaneHeader/            # Pane header bar components
│   │   │   ├── PaneHeaderView.swift       # Header bar with title, status dot, close button
│   │   │   ├── PaneHeaderDragSource.swift # AppKit drag source for pane rearrangement
│   │   │   ├── PaneHeaderCloseButton.swift # Close button with hover highlight
│   │   │   └── IDEHeaderButton.swift      # IDE open button with optional dropdown
│   │   ├── PaneDropZone.swift     # Drop zone calculation + overlay (ported from Ghostty)
│   │   ├── EmptyTerminalView.swift # Empty state placeholder
│   │   ├── ClaudePathResolver.swift   # Finds claude CLI binary
│   │   ├── TerminalEnvironment.swift  # Terminal env var configuration
│   │   ├── TerminalRegistry.swift  # Weak refs to terminals for sending input
│   │   ├── HookInstallationService.swift  # Claude Code hook setup
│   │   ├── HookInstallationPromptView.swift  # Hook install prompt UI
│   │   └── HookEventService.swift  # Reads hook events file
│   ├── IDE/                        # IDE detection & "Open in" integration
│   │   └── IDEDetectionService.swift  # Detects project type & installed IDEs
│   ├── Inspector/                  # Right-side inspector panel
│   │   └── InspectorPanelView.swift  # Session inspector (branch switcher, paths, permissions)
│   ├── Permissions/                # Permission configuration
│   │   ├── ClaudePermissions.swift        # Data types: ClaudePermissionMode, ClaudePermissions, ClaudePermissionSettings
│   │   ├── ClaudeSettingsService.swift    # Read/write ~/.claude/settings.json + project settings, merge logic
│   │   ├── SessionSettingsFileManager.swift # Per-session settings files in Application Support
│   │   ├── PermissionEditorView.swift     # Shared UI: mode picker, presets, rule lists, raw JSON
│   │   ├── PermissionRuleListView.swift   # Add/remove rule list component
│   │   └── RawPermissionsEditorView.swift # Raw JSON editor sheet
│   ├── Git/                        # Git integration
│   │   ├── GitChangedFile.swift    # Git changed file model
│   │   ├── GitStatusService.swift  # Git status detection
│   │   ├── GitChangesService.swift # Git tree loading & diff fetching
│   │   ├── GitChangesView.swift    # Git changes tree view
│   │   ├── GitChangedFileTreeNode.swift  # Recursive tree node
│   │   ├── GitChangedFileRow.swift # Git file row
│   │   ├── DiffView.swift          # Git diff viewer
│   │   ├── GitBranchService.swift  # Branch detection & listing (filesystem, no subprocess)
│   │   ├── WorktreeService.swift    # Git worktree creation, branch creation & git init
│   │   └── NewSessionDialogView.swift # Unified dialog for new sessions and splits (git/no-git)
│   ├── Settings/                   # Settings
│   │   ├── AppSettings.swift       # User preferences (UserDefaults) + AppearanceMode
│   │   ├── ClaudeThemeSync.swift   # Writes theme to ~/.claude.json on appearance change
│   │   ├── KeychainService.swift   # macOS Keychain storage for sensitive data (env vars)
│   │   └── SettingsView.swift      # App preferences view
│   └── Updates/                    # Update checker
│       ├── UpdateService.swift     # GitHub releases API + brew install
│       ├── UpdatePromptView.swift  # Bottom-right update prompt overlay
│       └── ReleaseNotesView.swift  # Release notes window on new version
├── Core/
│   ├── AppDatabase.swift           # GRDB DatabasePool setup + migrations
│   ├── SessionRecord.swift         # GRDB model + @Query request types
│   ├── SessionStore.swift          # Sole DB write service (ViewModels/services → DB)
│   ├── AppModel.swift              # Shared singleton (sessions, runtime, registry)
│   ├── ClaudeSessionModel.swift    # Observable facade: ClaudeSession + SessionRuntimeInfo
│   └── Extensions/
│       └── ClaudeSessionModel+Preview.swift  # Preview mocks for ClaudeSessionModel
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
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database for persistent session storage |
| [GRDBQuery](https://github.com/groue/GRDBQuery) | `@Query` property wrapper for reactive SwiftUI observation of GRDB |
| [gitdiff](https://github.com/tornikegomareli/gitdiff) | Diff rendering |
| [CodeEditor](https://github.com/ZeeZide/CodeEditor) | Syntax-highlighted code editor (bash init script in Settings & split dialogs) |

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

**Process enumeration**: `ProcessPoller` uses `sysctl(KERN_PROC_ALL)` + `KERN_PROCARGS2` + `proc_pidinfo(PROC_PIDTASKINFO)` — pure kernel syscalls, no subprocess fork. Forking via `Process()`/`ps` deadlocks when Ghostty is active because Ghostty installs a `SIGCHLD` handler that reaps all child processes (including `ps`) before `waitUntilExit()` can observe the exit.

**PID discovery**: `SessionStateMonitor` receives a `pidProvider` closure that queries Ghostty's `surface.foregroundPid`. This returns the `login` process PID (Ghostty's PTY child). The monitor walks down the process tree via `findLeafDescendant` to find the actual process we launched (e.g. `login → claude`). Once the leaf PID is found in the `ProcessPoller` snapshot, it's locked in for the monitor's lifetime. If the locked PID disappears, the provider is re-queried and the leaf walk repeats to discover a replacement. No process arg-matching or name checking — we trust the PTY ancestry chain.

### Persistent Session Store (GRDB)

Sessions are stored in a local SQLite database at `~/Library/Application Support/Tenvy/sessions.sqlite` using GRDB + GRDBQuery.

**Architecture**: `SessionStore` is the sole service that writes to the DB. Views never write directly — they observe via GRDBQuery's `@Query` property wrapper and emit actions to ViewModels/services.

**Session ID mapping**: When Claude is launched from Tenvy, the `TENVY_TERMINAL_ID` env var is set to the session's `terminalId`. The hook script includes this in JSONL events as `terminal_id`. When the first hook event arrives with both `session_id` (Claude's) and `terminal_id` (ours), `SessionStore.updateHookState()` writes the mapping to DB — instant, reliable sync with no heuristic matching.

**What's in the DB**: Session identity (`terminalId`, `claudeSessionId`), paths (`workingDirectory`, `projectPath`), display state (`title`, `hookState`, `currentTool`), metadata (`branchName`, `worktreePath`, `isPlainTerminal`, `isActive`).

**What stays in-memory**: CPU/memory/PID metrics (`SessionRuntimeInfo`) — changes every 500ms, meaningless after restart.

**Write discipline**: Views → Action enum → ViewModel → `SessionStore`. Services (HookEventService, SessionManager) → `AppModel.wireCallbacks()` → `SessionStore`.

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

**Terminal ID mapping**: Each hook event includes `terminal_id` (from `TENVY_TERMINAL_ID` env var). This enables instant, reliable mapping of Claude's `session_id` to Tenvy's `terminalId` — no heuristic matching needed. Events from sessions not launched by Tenvy have `terminal_id: null`.

### Notifications

- `NotificationService` uses `UNUserNotificationCenter` with `@Observable`
- `willPresent`: suppresses notification only when the session is in the **key window**; shows it for background windows
- On app focus: clears notification only for the **focused session window** (not all sessions) — prevents wiping dedup guard for background sessions
- Permission responses: `allowOnce` → Enter (`\r`), `allowSession` → ↓+Enter; optimistically clears `waitingPermission` hookState immediately
- `NSUserNotificationAlertStyle = alert` in Info.plist for persistent (non-disappearing) banners

### Terminal Environment

Claude is launched **through the user's login shell** with a configurable init script:

```
zsh -l -c '<init-script>; exec /path/to/claude [args]'
```

- **Shell Init Script**: Configurable in **Settings → Shell Init Script** using a syntax-highlighted bash editor (CodeEditor library). Default: `[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null;`. Stored in `AppSettings.shellInitScript` (UserDefaults key `settings.shellInitScript`).
- **Per-split override**: Split dialogs (WorktreeSplitView, NoGitSplitView) have a "Terminal" tab with a segmented control, allowing per-split init script customization. Overrides are stored in `ContentViewModel.splitInitScripts` and consumed on first terminal launch.
- `-l` sources `/etc/zprofile` and `~/.zprofile`
- The init script runs before `exec` (not via `-i` which triggers `/etc/zshrc` terminal key-binding setup and causes errors without a TTY)
- `exec` replaces the shell with claude at the same PID — process tracking is unaffected
- `LANG=en_US.UTF-8` is set if missing (GUI apps launched by launchd don't inherit it)
- Custom environment variables can be added in **Settings → Environment Variables** — stored in macOS Keychain (encrypted at rest), applied after the init script runs
- **Migration**: Old `sourceZshrc` boolean setting is automatically migrated to the new string format

### Process Cleanup

- **Kill target**: `runtimeInfo.shellPid` when set (legacy); `runtimeInfo.pid` (sysctl-discovered claude PID) as fallback for Ghostty sessions where `shellPid` is always 0
- `ProcessManager.terminateProcess` sends SIGTERM then SIGKILL after 100 ms; child processes are found via `sysctl(KERN_PROC_ALL)` (not `ps`) for the same SIGCHLD-deadlock reason
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
- **`PaneSplitTreeRenderer`** (private struct in `ContentView`): recursively renders the tree — `leaf` → `PaneLeafView`, `split` → `PaneSplitView` with two recursive renderers.
- **`PaneLeafView`** (private struct in `ContentView`): wraps each terminal in a `VStack` with `PaneHeaderView` on top and a drop zone overlay. Used in both single-pane and split modes.
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
- **Container wrapper**: `makeNSView` returns `GhosttyHostViewContainer` (thin NSView wrapper), not `GhosttyHostView` directly. SwiftUI manages the container's lifecycle — when a split tree change destroys the old wrapper, only the container is removed. The actual `GhosttyHostView` survives in the ViewModel cache. This mirrors Ghostty's `SurfaceScrollView`/`SurfaceRepresentable` pattern.
- **Cross-window transfer**: `handleDragToNewWindow` extracts the host view from the source cache, creates a new `ContentViewModel` with `preloadForTransfer()` (host view pre-loaded), then creates the new window via `NSWindow` + `NSHostingController` (not `NSApp.sendAction(newWindowForTab)`). The source split tree is modified AFTER the new window has the host view — no orphan gap.

#### Pane Headers & Drag-to-Rearrange

Every pane (single or split) has a `PaneHeaderView` at the top: 30px height, session title left-aligned, close button right-aligned. The header is the drag source for rearranging panes.

**Drag source**: `PaneHeaderDragSourceNSView` (AppKit `NSDraggingSource`) — follows Ghostty's `SurfaceDragSourceView` pattern. Encodes the pane's `terminalId` (String) on the pasteboard using custom type `com.tenvy.paneId` (registered as `UTType` in `Info.plist`). Creates a 20%-scaled terminal snapshot as the drag preview image. Escape key cancels the drag.

**Drop target**: `PaneDropDelegate` (SwiftUI `DropDelegate`) on each `PaneLeafView`. Uses `PaneDropZone` (ported from Ghostty's `TerminalSplitDropZone`) for triangular edge detection — the cursor's nearest edge determines the split direction (top/bottom/left/right). A colored overlay shows where the split will appear.

**Move operation**: `PaneSplitTree.moving(sessionId:toDestination:direction:)` removes the source pane from the tree and inserts it adjacent to the destination in the drop zone direction. This matches Ghostty's `splitDidDrop` behavior (remove-then-insert). `ContentViewModel.movePaneToSplit()` maps terminal IDs to session IDs and updates the tree.

**Title source**: Claude sessions use `session.title`; plain terminals use `GhosttyEmbedSurface.title` (auto-updates from terminal escape sequences via `@Published`).

**Drag outside window**: When a drag ends outside all visible windows, `Notification.paneDragEndedNoTarget` fires. `ContentViewModel.handlePaneDragToNewWindow` handles it: solo sessions (no split) are a no-op; split panes are transferred to a new AppKit-created window via `handleDragToNewWindow` (see GhosttyHostView Cache above).

#### File Drag & Drop

File drops into the terminal use a dual-path implementation because SwiftUI's hosting layer blocks AppKit drag events from reaching child NSViews in single-pane mode:

- **Split mode (AppKit)**: `GhosttyHostView.setupSurface()` calls `surfaceView.unregisterDraggedTypes()` then registers itself for `[.string, .fileURL, .URL]`. Its `draggingEntered`/`draggingExited`/`performDragOperation` overrides handle the drop and fire `TerminalAction.fileDragEntered`/`.fileDragExited`/`.fileDropped` → `PaneLeafView.handleAction()` updates `viewModel.fileDropTargetTerminalId` (header highlight) and calls `viewModel.focusPane()` (focus on drop).
- **Single-pane mode (SwiftUI fallback)**: `.onDrop(of: [.fileURL], isTargeted:)` applied **after** `.allowsHitTesting()` in `DetailView`. The `isTargeted` binding syncs to `viewModel.fileDropTargetTerminalId` via `onChange`. Drop handler calls `viewModel.handleSinglePaneFileDrop()` which shell-escapes paths and sends via `surface.sendText()`.
- **Header highlight**: `PaneHeaderView.isFileDropTarget` drives a pulsing accent-color background animation. State is unified through `viewModel.fileDropTargetTerminalId` — set by AppKit callbacks (split) or SwiftUI `isTargeted` (single-pane).
- **Shell escaping**: `GhosttyHostView.shellEscape()` mirrors Ghostty's `Shell.escape()` (which is internal to GhosttyEmbed). Escapes `\ ()[]{}<>"'\`!#$&;|*?\t`.

### Ghostty Terminal Backend

Three-layer architecture with clear separation of concerns:

- **`GhosttyHostView`** (NSView): generic terminal host — surface lifecycle, focus, layout, optional process monitoring. Does NOT know about Claude sessions or plain terminals. Exposes `setupSurface()` and `setupMonitoring()` as composable building blocks.
- **`ClaudeSessionTerminalView`** (NSViewRepresentable): Claude Code sessions — builds CLI command, calls both `setupSurface` + `setupMonitoring`, owns session-specific context menu (Copy, Paste, Splits, Rename Session, Close Session).
- **`PlainTerminalView`** (NSViewRepresentable): plain login shell — calls only `setupSurface` (no monitoring), owns terminal-specific context menu (Copy, Paste, Splits, Reset Terminal, Rename Terminal, Close Terminal).

**Action pattern**: Views communicate upstream via `TerminalAction` enum and a single `onAction: (TerminalAction) -> Void` handler (no callback closures).

**Launch**: both views write a temp shell script to `NSTemporaryDirectory()`, run `zsh -l /tmp/tenvy-UUID.sh` so `~/.zprofile` is sourced; script deleted in `deinit`.

**Context menu**: SwiftUI `.contextMenu { }` does NOT work on these views — Ghostty's `SurfaceView` overrides `menu(for:)` and intercepts right-clicks at the AppKit level before SwiftUI sees them. Fix: `GhosttyHostView` installs `NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown)` to intercept before Ghostty, then calls `contextMenuProvider` (set by the owning view) to get the menu. Menu action targets are stored on `hostView.menuTarget` to stay alive while the menu is open.

- Resize: `GhosttyHostView.layout()` calls `surface.notifyResize(bounds.size)` → `surfaceView.sizeDidChange(_:)`
- Input: `GhosttyInputProxy` conforms to `TerminalInputSender`; restart is a no-op (Ghostty doesn't support programmatic restart)

### Permission Configuration

Two-level permission management: global (App Settings) and per-session (Inspector Panel).

**Global permissions**: Read/write `~/.claude/settings.json` via `ClaudeSettingsService`. Preserves other keys (hooks, plugins) when writing. Exposed in Settings → "Claude Permissions" section.

**Per-session permissions**: Stored as JSON in `SessionRecord.permissionSettings` column (GRDB). On session creation, `ContentViewModel.insertSessionRecord()` merges global + project permissions via `ClaudeSettingsService.mergeForNewSession()`. Users can customize per-session in the Inspector Panel.

**Launch integration**: `ClaudeSessionTerminalView.makeNSView()` reads permission settings from DB and passes `--permission-mode`, `--allowedTools`, and `--disallowedTools` CLI flags. CLI flags are additive, so tools the user removed from the inherited allow list are automatically passed as `--disallowedTools` (deny overrides allow in Claude Code). The launched-with state is recorded as a SHA-256 hash in `SessionRecord.launchedPermissionsHash`.

**Live changes**: Per-session permission edits are saved to DB immediately but don't take effect on the running CLI until restart. Inspector shows a warning on first edit and a "Restart with New Permissions" button when `sessionPermissions.contentHash != launchedPermissionsHash`. Restart shows a confirmation dialog, then kills the process, evicts the cached GhosttyHostView, and bumps `terminalViewGenerations` to force SwiftUI to recreate the terminal (triggering a fresh `makeNSView`).

**Shared UI**: `PermissionEditorView` is used by both Settings (global) and Inspector (per-session). Takes `Binding<ClaudePermissionSettings>`. Includes mode picker, preset toggles, allow/deny/ask rule lists, and raw JSON editor sheet.

### Update Checker

- `UpdateService` checks GitHub releases API on every launch, compares with `AppInfo.version`
- Shows `UpdatePromptView` overlay (bottom-right) when a newer version is available
- Update runs `brew install --cask --force rostmen/tenvy/tenvy` silently via `Process` (no Terminal window)
- In-app progress states: `idle → installing → success → failed`
- On success: opens `/Applications/Tenvy.app` then terminates current process
- `isUpdating: Bool` flag bypasses quit/close confirmation dialogs when brew sends terminate signal
- Release notes fetched from GitHub release body and shown in a dark `NSWindow` on first launch of a new version

### Inspector Panel

- Collapsible right-side panel using SwiftUI `.inspector()` modifier — divider extends through the navigation bar (Xcode-style)
- Toggle: toolbar button (`sidebar.trailing` icon) or **⌘⌥I** (View > Toggle Inspector menu command via `Notification.toggleInspectorPanel`)
- State: `ContentViewModel.showInspectorPanel`
- Content renders only when `selectedSession` is non-nil; updates immediately on focus change
- **Branch section**: `Picker` dropdown with current branch selected. Other local branches shown below a divider, excluding worktree-checked-out branches. `GitBranchService.worktreeBranches(at:)` reads `.git/worktrees/*/HEAD` (filesystem, no subprocess). `GitBranchService.checkoutBranch(_:at:)` runs `git checkout`; on failure shows alert with git error message.
- **Paths section**: Working directory and project path with `~` abbreviation, folder icon (fills on hover) reveals in Finder

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

### Action Enum Pattern

Use action enums instead of multiple `on*` callback closures in views:

```swift
enum Action {
  /// Description of what this action does
  case someAction(param: Type)
}

// In views:
let onAction: (Action) -> Void

// In ViewModels:
func handle(action: Action) {
  switch action { ... }
}
```

Structural/lifecycle params (`existingHostView`, `onHostViewCreated`) stay as separate params — they're configuration, not actions.

---

## Claude Code Workflow Rules

**Git commits and pushes:**
- **DO NOT** commit or push until the user explicitly verifies the changes are good
- Always wait for user approval before running `git commit` or `git push`

**Documentation on architecture changes:**
- **ALWAYS** update CLAUDE.md architecture diagram when adding/removing/renaming files
- **ALWAYS** update "Critical Implementation Details" when adding new patterns or constraints
- **ALWAYS** update memory files (`.claude/` in repo) for non-obvious findings
- Do this as part of the implementation, not as an afterthought

---

## Maintenance Notes

**IMPORTANT**: Keep documentation updated when making changes:

- Update [FEATURES.md](./FEATURES.md) for feature changes
- Update architecture diagram when adding/removing files
- Update dependencies when adding new packages
- Update hook event table when adding new hook events
