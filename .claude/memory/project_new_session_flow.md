---
name: New Session Creation Flow
description: How the "+" sidebar button creates sessions — folder picker, git detection, unified dialog, tab/window routing
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

## Git Detection & Unified Dialog

`createNewSession()` always shows the `NewSessionDialogView` (unified dialog):

- **Git repo found**: Sets `hasGitRepo: true`. Dialog shows Branch/Worktree segment with full options.
- **No git repo**: Sets `hasGitRepo: false`. Dialog shows "Initialize git" checkbox with progressive disclosure.

Both paths populate `worktreeSplitForm` with defaults (branch name, worktree path, etc.).

See `project_new_session_dialog.md` for the complete dialog UX logic.

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
- `NewSessionDialogView.swift` — unified dialog for all session/split creation scenarios
