# Tenvy - Feature Documentation

A native macOS application for managing and resuming Claude Code CLI sessions with a transparent glass UI.

---

## Table of Contents

1. [Overview](#overview)
2. [Session Management](#session-management)
3. [Scheduled Tasks](#scheduled-tasks)
4. [Multi-Window & Tab System](#multi-window--tab-system)
5. [Terminal Integration](#terminal-integration)
6. [File Browser](#file-browser)
7. [IDE Integration](#ide-integration)
8. [Git Integration](#git-integration)
9. [Process Management](#process-management)
10. [UI Components](#ui-components)
11. [Settings & Preferences](#settings--preferences)
12. [Architecture Patterns](#architecture-patterns)

---

## Overview

Tenvy provides a native macOS interface for Claude Code CLI sessions with:

- **Session Discovery**: Automatically finds sessions from `~/.claude/projects/`
- **Embedded Terminal**: SwiftTerm-based terminal that runs Claude CLI directly
- **Multi-Window Support**: Each session runs in its own window/tab with process isolation
- **File Browser**: Project file tree with git status indicators
- **Git Changes View**: Modified files with syntax-highlighted diffs
- **Glass UI**: Transparent window with dark overlay and terminal cutout
- **Automatic Cleanup**: Processes are terminated when windows close or app quits

### Key Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator |
| [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) | Syntax highlighting |
| [gitdiff](https://github.com/tornikegomareli/gitdiff) | Diff rendering |

---

## Session Management

### Session Storage

Sessions are stored at: `~/.claude/projects/<encoded-path>/`

**Path Encoding:**
- `/Users/foo/project` → `-Users-foo-project`
- Leading slash removed, remaining slashes replaced with dashes

**Session File Format (`.jsonl`):**
```json
{"type":"summary","summary":"Session Title","leafUuid":"<uuid>"}
{"sessionId":"...","cwd":"...","timestamp":"..."}
```

### Session Model

```swift
struct ClaudeSession {
  let id: String           // UUID from filename
  let title: String        // From summary line
  let projectPath: String  // Encoded path
  let workingDirectory: String  // Current working dir
  let lastModified: Date   // File modification time
  let filePath: URL?       // Path to .jsonl file
  var isNewSession: Bool   // New vs existing
}
```

### Session Operations

| Operation | Description |
|-----------|-------------|
| **Load** | Scans `~/.claude/projects/` directories for `.jsonl` files |
| **Resume** | Launches Claude CLI with `--resume <session-id>` |
| **Create** | New session without `--resume` flag; shows worktree dialog if folder is git-controlled |
| **Rename** | Updates the summary line in `.jsonl` file |
| **Delete** | Removes `.jsonl` file and associated folder |

### Auto-Reload with FSEvents

Sessions automatically reload when files change:

- Uses kernel-level FSEvents API (efficient)
- 0.5 second latency batches rapid events
- Additional 0.3 second debounce prevents duplicate reloads
- Memory-safe with `Unmanaged` retain/release

---

## Scheduled Tasks

Recurring Claude Code "tasks" that run on a fixed schedule (minutes / hours / days / weeks), each firing as its own background window with a fresh Claude session pre-seeded with a user-provided prompt.

> Full design and decision log: [`scheduled-tasks.md`](./scheduled-tasks.md).

### Creating a task

The sidebar toolbar's existing **+** button is a split menu: clicking it directly opens the regular New Session flow, and its dropdown adds a **New Scheduled Task** item that opens `CreateScheduledTaskView`. The form collects:

- **Name** — used for session titles, branch slugs, and sidebar rows.
- **Working folder** — required. If it isn't a git repo, the user must opt in to a "git init on first run" checkbox.
- **Worktree base** (optional) — defaults to `<repo>/.claude/worktrees`.
- **Frequency** — unit (Minutes/Hours/Days/Weeks) + value (1–999). Days and weeks additionally take a time-of-day; weeks add a multi-select weekday picker.
- **Prompt** — segmented Text / File. Text is stored inline; file paths are re-read on every execution.
- **Permissions** — embedded `PermissionEditorView`, pre-filled from `ClaudeSettingsService.mergeForNewSession(...)`.

Saving validates the form, computes the first `nextRunAt` from the configured frequency, and inserts via `ScheduledTaskStore`. The first run waits for the first natural slot — it never fires immediately.

### Sidebar

A collapsible "Scheduled" section sits above the Active and by-date groups in the Sessions tab. Each row shows:

- A status icon (clock for waiting-next, play for running, slash for skipped, xmark for failed, pause for disabled).
- The task name.
- A relative-only countdown ("in 12s", "in 3m 45s", "in 3 days") that ticks live via a `TimelineView` whose refresh cadence scales to the remaining time.

Tapping a row pushes the sidebar into `ScheduledTaskDetailView`. The back chevron returns to the flat list. Expanded/collapsed state is persisted in `@AppStorage`.

### Task detail (push view)

`ScheduledTaskDetailView` shows a compact header (back chevron, task name, frequency summary, enable toggle, delete button), an expandable "Details" disclosure (folder, worktree base, permissions summary, prompt preview, last-run info), and the list of sessions ever spawned by this task. Tapping a session navigates to it normally.

### Execution

When the in-app scheduler decides a task is due, the executor:

1. Runs the **overlap rule** — see below.
2. Detects or initializes the git repo, creates a fresh worktree under `tenvy/scheduled/<slug>/<YYYYMMDD-HHMMSS>` (worktree dir name uses the same slug+timestamp).
3. Inserts a new `SessionRecord` linked to the scheduled task, with a title of the form `"<Task name> — yyyy-MM-dd HH:mm"` and the task's snapshotted permission settings.
4. Opens a new `NSWindow` via `NSHostingController<ContentView>` and calls `orderFront(nil)` — **without** `makeKeyAndOrderFront`. The window appears but doesn't steal focus from the user's foreground app.
5. Registers a one-shot prompt-injection listener; when the spawned session emits its `SessionStart` hook event, the injector resolves the window's `GhosttyHostView` and calls `surface.sendText(prompt)` followed by Enter 150 ms later.
6. Updates the task's `lastRunAt`, `lastRunStatus = .running`, `lastRunSessionId`, and the next computed `nextRunAt`.
7. Posts a "Scheduled task started" macOS notification.

### Overlap rule (one window per task at a time)

Before doing any work for a firing, the executor inspects the prior spawned session:

| Prior session state | Action |
|---|---|
| `waiting` (Stop hook fired — Claude is idle) | Auto-close the prior window/process, then proceed. |
| `processing`, `thinking`, `waitingPermission` | **Skip** the new run; record `.skipped` with reason. |
| `started` or no hook state yet | **Skip** (race-window guard — prior session might still be booting). |
| `ended` / prior session not active anymore | Proceed. |

Skipped runs do not appear in the sub-list (they didn't create a session), but they do surface on the task row as the current status with the reason text.

### Failures and missed runs

- Any error in the pipeline (folder missing, worktree creation failed, file prompt unreadable, `SessionStart` timed out at 60 s, etc.) marks the run as failed, flips `enabled = false` on the task, and posts a notification with the reason. The user must manually re-enable after fixing the cause.
- If the app was closed when a slot was due, the scheduler **does not** fire the missed run on launch — it only rolls `nextRunAt` forward to the next valid slot. Tasks never fire while Tenvy isn't running.

### Disable / re-enable / delete

- The detail view's toggle disables the task. If a session is currently running, a sheet asks the user whether to stop the running session or let it finish naturally before disabling.
- Re-enabling uses **a fresh anchor from re-enable time** — it does not preserve the original schedule.
- Editing is **not** supported. To change frequency, prompt, folder, or permissions, the user deletes and recreates.
- Deleting opens a stateful confirmation dialog that lists the task, the spawned session records, and the worktree directories that will be removed. Both "delete sessions" and "delete worktrees" are independently opt-in checkboxes (default on). On confirm the dialog enters a "Cleaning up…" state with a progress bar and per-step status text; it cannot be dismissed during this phase. On success it shows a checkmark and auto-closes. On partial failure it lists the items that couldn't be removed.

### Worktree retention

Spawned worktrees are **kept forever until the task itself is deleted** (decided trade-off — disk usage grows linearly with runs). The delete dialog is the canonical bulk-cleanup mechanism.

### Notifications

Every run start, every skip, and every failure dispatches a transient macOS notification via `NotificationService.notifyScheduledTaskEvent(...)`. Identifiers are unique per event so the OS doesn't dedupe across historical runs.

---

## Multi-Window & Tab System

### Window-Session Ownership

**Critical Invariant:** Each session has exactly ONE terminal and ONE process.

**Tracking Mechanisms:**

1. **WindowSessionRegistry** - Maps window numbers to session IDs
2. **NSWindow.sessionId** - Associated object fallback
3. **AppState.activatedSessions** - Sessions with active terminals

### Session Selection Flow

```
User clicks session in sidebar
        │
        ▼
┌─────────────────────────────────┐
│ Is session open in another      │
│ window?                         │
└──────────────┬──────────────────┘
               │
        ┌──────┴──────┐
        │ YES         │ NO
        ▼             ▼
┌──────────────┐ ┌─────────────────────┐
│ Switch to    │ │ Does current window │
│ existing     │ │ have a session?     │
│ window       │ └──────────┬──────────┘
└──────────────┘            │
                     ┌──────┴──────┐
                     │ YES         │ NO
                     ▼             ▼
              ┌──────────────┐ ┌──────────────┐
              │ Open in      │ │ Open in      │
              │ new tab      │ │ this window  │
              └──────────────┘ └──────────────┘
```

### New Tab Mechanism

```swift
// Store session for new tab
windowRegistry.pendingSessionForNewTab = session

// Trigger new tab creation
NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)

// New ContentView picks up pending session in onAppear
.onAppear {
  if let pending = windowRegistry.pendingSessionForNewTab {
    windowRegistry.pendingSessionForNewTab = nil
    selectedSession = pending
  }
}
```

### Terminal Render Conditions

Terminal only renders when ALL conditions are met:

```swift
if let session = selectedSession,           // 1. Session selected
   appState.isSessionActivated(session.id), // 2. Session activated
   windowConfigured,                        // 3. Window configured
   currentWindow?.sessionId == session.id { // 4. Window owns session
  TerminalView(...)
}
```

### Window Close Handling

When closing a window with an active session:

1. **Confirmation Dialog** appears with:
   - "Terminate Session" (destructive, red)
   - "Cancel"

2. **On Terminate:**
   - Kill shell process (kills Claude as child)
   - Reset runtime info (state, CPU, PIDs)
   - Remove from activated sessions
   - Unregister from window registry

---

## Terminal Integration

### Terminal Backends

Tenvy supports two terminal backends, selectable in **Settings → Terminal**:

| Backend | Default | Notes |
|---------|---------|-------|
| SwiftTerm | Yes | Lightweight, full color palette control |
| Ghostty | No | Full Ghostty terminal, respects user's Ghostty config |

Both backends launch Claude through a **login shell** (`zsh -l`) so `~/.zprofile` and `~/.zshrc` are sourced and PATH is correct (Homebrew, NVM, pyenv, etc.). For Ghostty, the shell script is written to a temp file to avoid quoting issues with Ghostty's command parser.

### SwiftTerm Configuration

| Setting | Value |
|---------|-------|
| TERM | `xterm-256color` |
| COLORTERM | `truecolor` |
| TERM_PROGRAM | `Tenvy` |
| Background (dark) | Black @ 50% opacity |
| Background (light) | White @ 55% opacity |
| Scrollers | Overlay style (thin, translucent) |

### Claude Process Discovery

Searches for Claude executable in order:
1. `/usr/local/bin/claude`
2. `/opt/homebrew/bin/claude`
3. `~/.local/bin/claude`
4. `/usr/bin/claude`
5. Falls back to `/usr/bin/env` (PATH lookup)

### PID Tracking

**Two PIDs are tracked:**

| PID Type | Purpose |
|----------|---------|
| Shell PID | Parent process, used for termination |
| Claude PID | Child process, used for CPU monitoring |

**Why separate?** Killing the shell PID terminates the entire process tree including Claude.

### Session State Monitoring

State is derived from CPU usage with rolling 3-sample average:

| State | CPU Threshold | Visual |
|-------|---------------|--------|
| `inactive` | Process not running | Gray dot |
| `waitingForInput` | < 3% | Green dot |
| `thinking` | > 25% | Yellow dot |

**State Machine Rules:**
- Must run for 5+ seconds before state changes
- Must be in state for 2+ seconds before transition
- CPU sampled every 0.5 seconds

### Claude Process Discovery

Finds the `airchat_cli_claude_code` process that:
1. Contains the session ID in its arguments
2. Is a descendant of the shell PID

Uses `ps -eo pid,ppid,args` and BFS traversal.

### Drag & Drop

Files can be dragged from Finder into any terminal pane:
- Paths are shell-escaped (spaces, parentheses, quotes, etc.)
- Multiple files joined with spaces
- Text inserted at cursor position
- **Header highlight**: Pane header pulses with accent color while a file drag hovers over the pane
- **Focus on drop**: Dropping on a non-focused split pane automatically selects and focuses it
- **Dual implementation**: Split mode uses AppKit-level drag handling on `GhosttyHostView`; single-pane mode uses a SwiftUI `.onDrop` fallback (SwiftUI's hosting layer blocks AppKit drag events from reaching child NSViews in single-pane mode)

### Pane Headers & Drag-to-Rearrange

Every terminal pane has a header bar (always visible):
- **Title**: Session name (Claude) or terminal title from escape sequences (plain terminals)
- **Close button**: Closes the pane; shows confirmation for active Claude sessions
- **Draggable**: Drag a header onto another pane to rearrange — drop zone overlay shows split direction (top/bottom/left/right)
- **Drop zones**: Triangular edge detection (ported from Ghostty) — cursor's nearest edge determines the split direction
- **Move operation**: Source pane is removed from its position and inserted at the destination (not a swap — matches Ghostty behavior)
- **Self-drop**: No-op

---

## File Browser

### File Tree Loading

**Background Loading:**
1. Git status fetched first (fast)
2. Directory traversal runs on background thread
3. Results cached in `FileTreeCache`
4. UI updates on main thread

**Sorting:**
- Directories first
- Alphabetical within each group
- Case-insensitive

**Filtering:**
- Hidden files (starting with `.`) are excluded

### Expansion Persistence

Expanded folders are persisted per project:

```swift
UserDefaults key: "FileTreeView.expandedPaths.<encoded-path>"
```

- Paths validated on load (removed if deleted)
- Saved on each expand/collapse

### File Icons

Icons determined by extension using SF Symbols:

| Extension | Icon |
|-----------|------|
| `.swift` | `swift` |
| `.js`, `.ts` | `doc.text` |
| `.json` | `curlybraces` |
| `.md` | `doc.richtext` |
| `.py` | `doc.text` |
| Folders | `folder.fill` |
| Default | `doc` |

---

## IDE Integration

### Open in IDE

A toolbar button detects the project type and installed IDEs, allowing one-click opening in the appropriate editor.

### Project Detection

The system scans the project directory for indicator files:

| Indicator Files | Primary IDE |
|---|---|
| `.xcodeproj`, `.xcworkspace`, `Package.swift` | Xcode |
| `build.gradle`, `build.gradle.kts`, `pubspec.yaml` | Android Studio |
| `.idea/`, `pom.xml` | IntelliJ IDEA |
| `Cargo.toml` | RustRover |
| `*.sln`, `*.csproj` | Rider |
| `go.mod` | GoLand |
| `package.json`, `tsconfig.json` | WebStorm |
| `Gemfile` | RubyMine |
| `requirements.txt`, `pyproject.toml`, `setup.py` | PyCharm |

### General-Purpose Editors

These are always offered when installed, regardless of project type: VS Code, Cursor, Windsurf, Zed, Sublime Text, Nova, Fleet.

### Pane Header Button

- Appears in the pane header bar (right side, before close button) for Claude sessions only — not for plain terminals
- **Single IDE**: Icon-only button, click to open
- **Multiple IDEs**: Icon with dropdown chevron — main click opens primary IDE, chevron shows alternatives
- Uses SwiftUI `Menu(primaryAction:)` for native macOS split button behavior
- IDE icons loaded from installed app bundles via `NSWorkspace`

### Detection Flow

1. List files in `session.projectPath` (falls back to `workingDirectory`)
2. Match against IDE indicator catalog
3. Check which IDEs are installed via `NSWorkspace.urlForApplication(withBundleIdentifier:)`
4. Results cached per project path to avoid re-scanning on focus changes

---

## Git Integration

### Status Detection

Uses `git status --porcelain -uall` for machine-readable output.

**Status Indicators:**

| Code | Status | Color |
|------|--------|-------|
| `M` | Modified | Yellow |
| `A` | Added | Green |
| `D` | Deleted | Red |
| `R` | Renamed | Blue |
| `?` | Untracked | Gray |
| `S` | Staged | Cyan |

**Parent Directory Marking:**
Directories containing changed files are marked as modified.

### Git Changes View

Shows only modified files in a tree structure:

1. Parses `git status` output
2. Builds tree from paths
3. Fetches unified diff for each file
4. Displays with syntax highlighting

### Diff Generation

| File Status | Diff Source |
|-------------|-------------|
| Modified | `git diff -- <file>` |
| Deleted | `git diff --cached -- <file>` |
| Untracked | Synthetic diff (all lines as `+`) |

**Synthetic Diff Format:**
```diff
diff --git a/newfile.txt b/newfile.txt
new file mode 100644
--- /dev/null
+++ b/newfile.txt
@@ -0,0 +1,10 @@
+line 1
+line 2
...
```

### Diff View

Uses [gitdiff](https://github.com/tornikegomareli/gitdiff) library:

- Dark theme
- Line numbers
- Comfortable line spacing
- Scrollable with header

### Git Branch Tracking

Displays the current git branch in the session sidebar row for sessions inside git repos.

- **`GitBranchService`**: Reads `.git/HEAD` directly — no subprocess, safe alongside Ghostty (avoids SIGCHLD deadlock)
- Supports worktrees (`.git` file with `gitdir:` pointer) and detached HEAD (short SHA)
- Branch resolves via `commondir` for worktree git dirs so `refs/heads/` is read from the main repo
- **`listLocalBranches(at:)`**: Enumerates `.git/refs/heads/` + parses `packed-refs` — pure filesystem, no subprocess
- Refreshed every 5 seconds via a `.task` timer in `ContentView`

### Worktree Dialog

The worktree creation dialog is shared between two flows: **split panes** (context menu) and **new session creation** ("+" sidebar button). Both intercept to offer git worktree creation when a git repo is detected.

**Trigger 1 — Split from context menu:** `TerminalAction.splitRequested` → checks `runtimeInfo.gitBranch`
**Trigger 2 — New session from "+":** `createNewSession()` → checks `WorktreeService.findRepoRoot(from: path)`

Both set `pendingSplit` (with `isNewSessionFlow` flag) and populate `worktreeSplitForm`, which triggers the dialog overlay.

**Git repo detected:**
- Dialog shows: base branch picker, new branch name field, worktree destination path, fork session toggle
- Base branch pre-selected to current session's branch
- Branch name defaults to `MM-dd-yyyy-HH-mm-session-name`
- Destination defaults to `<repo>/.claude/worktrees/<branch>/` (matches Claude CLI convention)
- Fork session toggle (hidden for unsaved sessions): launches `claude --resume <id> --fork-session`
- Header adapts: "New Session in Worktree" vs "Create Worktree Split"
- Skip button adapts: "Skip" (new session at original path) vs "Plain Terminal" (raw shell pane)
- On confirm: runs `git worktree add -b <branch> <path> <base>` then creates split pane or standalone session in worktree directory

**No git repo (split flow only):**
- Dialog offers: "Initialize Git & Create Worktree" (one-step: `git init` + `git worktree add`) or "Open Plain Terminal"
- Plain terminal opens a raw shell — untracked, no auto-close

**Implementation:**
- `PendingSplitRequest`: holds `isNewSessionFlow: Bool` to distinguish the two flows
- `WorktreeService`: Git operations via `Process()` — runs before Ghostty surface creation, so SIGCHLD safe
- `WorktreeSplitView` / `NoGitSplitView`: Dialog views with opaque background, centered overlay with dim backdrop
- `ContentViewModel`: `pendingSplit` state triggers dialog; `confirmWorktreeSplit()`, `initGitAndCreateWorktree()`, `openPlainTerminalSplit()` handle each path; new session flow uses `activateNewSession()` instead of `insertSplitPane()`
- Plain terminals skip all monitoring (`SessionStateMonitor` not started, auto-close disabled)

---

## Process Management

### ProcessManager Singleton

Tracks all spawned Claude processes for cleanup.

**Registration:**
```swift
ProcessManager.shared.registerProcess(pid: shellPid)
```

**Cleanup Triggers:**
1. Window close (user-initiated)
2. App quit (normal termination)
3. SIGTERM, SIGINT, SIGHUP signals
4. `atexit` handler (last resort)

### Process Tree Termination

```
terminateProcessTree(shellPid)
        │
        ▼
┌─────────────────────────┐
│ Find all child processes│
│ via ps + BFS traversal  │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Kill children first     │
│ (bottom-up order)       │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Kill parent shell       │
└─────────────────────────┘
```

**Kill Sequence:**
1. Send SIGTERM (graceful)
2. Wait 100ms
3. Check if still running
4. Send SIGKILL if needed (force)

### Signal Handlers

```swift
signal(SIGTERM) { _ in ProcessManager.shared.terminateAllProcesses(); exit(0) }
signal(SIGINT)  { _ in ProcessManager.shared.terminateAllProcesses(); exit(0) }
signal(SIGHUP)  { _ in ProcessManager.shared.terminateAllProcesses(); exit(0) }
```

---

## UI Components

### Window Glass Effect

```swift
NSVisualEffectView:
  material = .underWindowBackground
  blendingMode = .behindWindow
  state = .active
  isEmphasized = true

NSWindow:
  titlebarAppearsTransparent = true
  styleMask.insert(.fullSizeContentView)
  isOpaque = false
  backgroundColor = .clear
```

### Dark Overlay with Cutout

```swift
Canvas { context, size in
  // Fill with semi-transparent black
  context.fill(
    Path(CGRect(origin: .zero, size: size)),
    with: .color(.black.opacity(0.5))
  )

  // Cut out terminal area
  if terminalFrame != .zero {
    context.blendMode = .destinationOut
    context.fill(Path(terminalFrame), with: .color(.white))
  }
}
```

### Inspector Panel

Collapsible right-side panel using SwiftUI's `.inspector()` modifier (Xcode-style full-height divider). Toggle via toolbar button or **⌘⌥I** (View > Toggle Inspector).

**Sections:**
- **Branch** — Picker dropdown showing current git branch. Lists all local branches except those checked out in worktrees. Selecting a branch runs `git checkout`; on failure (e.g. uncommitted conflicts), an alert shows the git error.
- **Paths** — Working directory and project path with `~` abbreviation. Each path has a folder icon (fills on hover) that reveals in Finder.

**State:** `ContentViewModel.showInspectorPanel` — toggled via toolbar button or `Notification.toggleInspectorPanel` (⌘⌥I menu shortcut). Panel only renders content when `selectedSession` is non-nil.

**Branch data:** `GitBranchService.worktreeBranches(at:)` reads `.git/worktrees/*/HEAD` to identify branches checked out in worktrees (excluded from dropdown). `GitBranchService.checkoutBranch(_:at:)` runs `git checkout` and returns error string on failure.

### Sidebar Tabs

| Tab | Icon | Content |
|-----|------|---------|
| Sessions | `clock.arrow.circlepath` | Session list |
| Files | `folder` | File tree |
| Changes | `arrow.triangle.branch` | Git changes |

**Tab State Preservation:**
All views kept alive in ZStack with opacity toggle (prevents state loss on tab switch).

### Session Row

```
┌──────────────────────────────────────────┐
│ ● Session Title                   12.5%  │
│ Mar 21, 10:30 AM • ~/project/path        │
│ PID: 12345                               │
└──────────────────────────────────────────┘
```

- Green dot: waiting for input
- Yellow dot: thinking
- Gray dot: inactive
- CPU percentage color-coded (green/orange/yellow)

---

## Settings & Preferences

### Feature Toggles

| Setting | Default | Description |
|---------|---------|-------------|
| Git Changes | Disabled | Show Changes tab in sidebar |
| Terminal | SwiftTerm | Terminal backend: SwiftTerm or Ghostty |
| Appearance | System | Light / Dark / System color scheme |
| Source ~/.zshrc | Enabled | Source ~/.zshrc before launching Claude |

### Appearance Mode

Tenvy supports three appearance modes selectable in **Settings → Appearance**:

| Mode | Behavior |
|------|----------|
| System | Follows macOS appearance automatically |
| Light | Forces light mode across all windows |
| Dark | Forces dark mode across all windows |

On change:
- All windows (main, Settings, Release Notes) update immediately via `preferredColorScheme`
- `ClaudeThemeSync` writes `"theme": "dark"|"light"` to `~/.claude.json` so Claude CLI output colors match
- Sessions with `hookState == .waiting` are restarted automatically so the new theme takes effect; busy sessions are left alone

### Permission Configuration

Two-level permission management for Claude Code:

**Global Permissions** (Settings → Claude Permissions):
- Permission mode picker: Default, Accept Edits, Plan, Auto, Bypass Permissions
- Allow/Deny/Ask rule lists with add/remove (e.g., `Bash(git *)`, `Edit`, `WebFetch(domain:example.com)`)
- Quick preset toggles: "Allow all file edits", "Allow all bash commands", "Allow web access", "Allow all MCP tools"
- Raw JSON editor for power users
- Reads/writes `~/.claude/settings.json` (preserving hooks, plugins, etc.)

**Per-Session Permissions** (Inspector Panel → Permissions):
- Each new session inherits merged global + project permissions at creation
- Users can customize per-session in the Inspector; changes saved to DB immediately
- Changes require session restart — warning banner + "Restart with New Permissions" button (with confirmation dialog)
- Restart button uses SHA-256 hash comparison: appears only when current permissions differ from launched-with state
- "Reset to Inherited" button reverts to merged global + project settings
- Stored in GRDB as JSON column on SessionRecord

**Launch Integration**:
- Per-session permissions passed as CLI flags: `--permission-mode`, `--allowedTools`, `--disallowedTools`
- CLI flags are additive, so tools removed from the inherited allow list are automatically denied via `--disallowedTools` (deny overrides allow in Claude Code)
- Launched-with state recorded as SHA-256 hash in `SessionRecord.launchedPermissionsHash`

### Persisted Data

| Key | Storage | Purpose |
|-----|---------|---------|
| `SuppressQuitAlertForActiveSessions` | UserDefaults | Don't ask on quit |
| `FileTreeView.expandedPaths.*` | UserDefaults | Expanded folders |
| `settings.gitChangesEnabled` | UserDefaults | Feature toggle |
| `settings.terminalType` | UserDefaults | SwiftTerm or Ghostty |
| `settings.appearanceMode` | UserDefaults | Light / Dark / System |
| `settings.sourceZshrc` | UserDefaults | Source ~/.zshrc on launch |
| `customEnvironmentVariables` | macOS Keychain (JSON) | Extra env vars (encrypted at rest) |

---

## Architecture Patterns

### State Management

| Pattern | Usage |
|---------|-------|
| `@Observable` | `SessionRuntimeInfo` - fine-grained reactivity |
| `@ObservableObject` | `AppState`, `SessionManager` - shared state |
| `@State` | Local view state |
| `@Binding` | Parent-child communication |

### Singletons

| Singleton | Purpose |
|-----------|---------|
| `AppState.shared` | App-wide state coordination |
| `ProcessManager.shared` | Process tracking and cleanup |
| `FileTreeCache.shared` | Cached file trees |
| `WindowSessionRegistry.shared` | Window-session mapping |
| `AppSettings.shared` | User preferences |

### Thread Safety

| Component | Thread | Mechanism |
|-----------|--------|-----------|
| ProcessManager | Any | NSLock |
| SessionManager | Main | @MainActor |
| FileTreeCache | Main (load on background) | Task.detached + MainActor.run |
| SessionStateMonitor | Utility queue | DispatchSourceTimer |

### Memory Management

| Scenario | Solution |
|----------|----------|
| FSEvents callback | `Unmanaged` retain/release |
| Timer in monitor | Weak self capture |
| Terminal view | `registeredPID` cleanup in `deinit` |

---

## Color Palette

### Theme Colors

| Name | Hex | Usage |
|------|-----|-------|
| Background | `#000000` @ 70% | Window background |
| Surface | `#1a1a1a` | Cards, panels |
| Text Primary | `#eaeaea` | Main text |
| Text Secondary | `#8b8b9e` | Labels, hints |
| Accent | `#da7756` | Claude orange |

### Terminal ANSI Colors

| Index | Color | Hex |
|-------|-------|-----|
| 0 | Black | `#000000` |
| 1 | Red | `#c2361f` |
| 2 | Green | `#25bc24` |
| 3 | Yellow | `#adad27` |
| 4 | Blue | `#492ee1` |
| 5 | Magenta | `#d338d3` |
| 6 | Cyan | `#33bbc8` |
| 7 | White | `#cbcccd` |

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Session file parse error | Silently skipped |
| `~/.claude/projects` missing | Empty session list |
| Git not available | Empty status, no indicators |
| Process already terminated | Gracefully ignored |
| Window delegate not set | Notification observer fallback |

---

## Build & Run

```bash
# Build
xcodebuild -scheme Tenvy -destination 'platform=macOS' build

# Or open in Xcode
open Tenvy.xcodeproj
# Press Cmd+R
```

**Requirements:**
- macOS 14.0+
- Xcode 15.0+
- Claude CLI installed

**Note:** App sandbox is disabled to allow:
- Access to `~/.claude`
- Spawning `claude` CLI process
- Reading project files
