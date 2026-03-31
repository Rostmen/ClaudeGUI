# Tenvy - Feature Documentation

A native macOS application for managing and resuming Claude Code CLI sessions with a transparent glass UI.

---

## Table of Contents

1. [Overview](#overview)
2. [Session Management](#session-management)
3. [Multi-Window & Tab System](#multi-window--tab-system)
4. [Terminal Integration](#terminal-integration)
5. [File Browser](#file-browser)
6. [Git Integration](#git-integration)
7. [Process Management](#process-management)
8. [UI Components](#ui-components)
9. [Settings & Preferences](#settings--preferences)
10. [Architecture Patterns](#architecture-patterns)

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
