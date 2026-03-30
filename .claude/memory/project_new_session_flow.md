---
name: New Session Creation Flow
description: How the "+" sidebar button creates sessions — folder picker, git detection, worktree dialog, tab/window routing
type: project
---

# New Session Creation Flow

The "+" button in the sidebar toolbar creates new Claude Code sessions.

## Signal Path

```
SessionListView "+" toolbar button
  → createNewSession() (private, opens NSOpenPanel)
    → creates ClaudeSession(id: UUID, title: "New Session", path: selected folder, isNewSession: true)
    → onAction(.createNew(session))
      → SidebarView passes through
        → ContentView calls viewModel.handleSessionListAction(.createNew)
          → ContentViewModel.createNewSession(session)
```

## Git Detection & Worktree Dialog

`createNewSession()` checks `WorktreeService.findRepoRoot(from: path)`:

- **Git repo found**: Shows the worktree dialog (`WorktreeSplitView`) via `pendingSplit` with `isNewSessionFlow: true`. Uses `GitBranchService.currentBranch(at:)` and `listLocalBranches(at:)` for branch info (filesystem-based, no subprocess). User can:
  - "Create Worktree" → creates worktree, then `activateNewSession()` at worktree path
  - "Skip" → `activateNewSession()` at original path (no worktree)
  - "Cancel" → dismisses dialog, no session created

- **No git repo**: Calls `activateNewSession()` directly (no dialog).

## Session Activation (`activateNewSession`)

Routes based on whether a session already exists in the window:

- **Has existing session** → opens in new tab: sets `pendingSessionForNewTab`, triggers `newWindowForTab`
- **No existing session** → opens in current window: `appModel.activateSession()` + `setSelectedSession()`

## Key Types

- `SessionListAction.createNew(ClaudeSession)` — action enum case
- `ClaudeSession(isNewSession: true)` — flag means session file doesn't exist yet; `syncNewSessionWithDiscoveredSession()` updates it when Claude CLI creates the real session file

## Key Files

- `SessionListView.swift` — "+" button, `createNewSession()`, NSOpenPanel
- `ContentViewModel.swift` — `createNewSession()` (git check + dialog), `activateNewSession()` (tab/window routing)
- `WorktreeSplitView.swift` — shared dialog (adapts header/buttons based on `isNewSessionFlow`)
