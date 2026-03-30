---
name: New Session Dialog
description: Unified NewSessionDialogView — the single dialog for both "+" new sessions and split pane creation, covering all git/no-git scenarios
type: project
---

# New Session Dialog (NewSessionDialogView)

A unified modal dialog that replaces the old `WorktreeSplitView` and `NoGitSplitView`. Handles all combinations of new session / split pane creation across git and non-git directories.

## Entry Points

1. **"+" button** (new session): `SessionListView` → folder picker → `ContentViewModel.createNewSession(_:)` → sets `pendingSplit` with `isNewSessionFlow: true`
2. **Context menu split**: `TerminalAction.splitRequested` → `ContentViewModel.handleSplitRequested(direction:)` → sets `pendingSplit` with `isNewSessionFlow: false`
3. **Plain terminal split**: Same as #2, but detected via `isPlainTerminal(terminalId)` → sets `isPlainTerminalSplit: true`, skips git entirely

## Data Models

### PendingSplitRequest
```swift
struct PendingSplitRequest {
  let direction: SplitDirection
  let sourceSession: ClaudeSession
  let hasGitRepo: Bool
  let isNewSessionFlow: Bool          // true for "+" button, false for splits
  let isPlainTerminalSplit: Bool      // true when splitting from a plain terminal
}
```

### WorktreeSplitFormData
```swift
struct WorktreeSplitFormData {
  var baseBranch: String
  var newBranchName: String           // auto-generated: "MM-dd-yyyy-HH-mm-<session-title>"
  var worktreePath: String            // auto-updated from branch name
  var forkSession: Bool = false
  var initSubmodules: Bool = true
  var symlinkBuildArtifacts: Bool = true
  var availableBranches: [String]
  let sourceSessionId: String
  let sourceIsNewSession: Bool
  let repoRoot: String
  var initScript: String              // shell init script (from AppSettings)
  var initGit: Bool = false           // whether to run git init (no-git flows)
  var createBranch: Bool = false      // whether to create a new branch
  var gitMode: GitMode = .worktree    // .branch or .worktree
}
```

## Dialog UX Logic

### Top-level tabs: `[Git | Shell Init Script]`

Plain terminal splits skip this entirely — they only show Shell Init Script + "Create" button.

### Git Tab — 4 Context Variants

#### New Session + No Git (A1)
```
[ ] Initialize git (i)
└─ checked:
   [ ] Create branch (i)
   └─ checked:
      [Branch | Worktree] segment
      Branch: name + base ("main")
      Worktree: name + base ("main") + destination + submodules
```

#### New Session + Git (A2)
```
[Branch | Worktree] segment
Branch tab:
  Current branch: <name>
  [ ] Create new branch (i)
  └─ checked: name + base branch picker
Worktree tab:
  name + base + destination + submodules
[ ] Fork session (i) — only if not sourceIsNewSession
```

#### Split + No Git (B1)
```
Warning: "This folder is not a git repository."
[ ] Initialize git (i)
└─ checked:
   [Branch (disabled) | Worktree (selected)] segment
   Worktree: name + base ("main") + destination + submodules
"Start" disabled until init git + worktree configured
```

#### Split + Git (B2)
```
[Branch (disabled) | Worktree (selected)] segment
Worktree: name + base + destination + submodules
[ ] Fork session (i) — only if not sourceIsNewSession
```

#### Plain Terminal Split
```
Shell Init Script editor only
Buttons: [Cancel] [Create]
```

### Branch tab disabled for splits
Creating a branch without a worktree means both panes share the same directory — file collision risk. Only worktree mode is allowed for splits.

### Branch name shared between tabs
When user switches between Branch and Worktree mode, the `newBranchName` persists. The worktree path auto-update (`onChange`) only fires when `gitMode == .worktree`.

## Bottom Buttons

| Button | Action |
|--------|--------|
| **Cancel** | Dismiss dialog |
| **Terminal Only** | Apply git settings + open as plain shell (no Claude) |
| **Start** | Apply git settings + open as Claude session |

### Button Enablement

| Context | Start | Terminal Only |
|---------|-------|---------------|
| New session, no git, init unchecked | Enabled | Enabled |
| New session, no git, init checked, no branch | Enabled | Enabled |
| New session, git, branch tab, create unchecked | Enabled | Enabled |
| New session, git, branch/worktree, name empty | Disabled | Enabled |
| Split, no git, init unchecked | **Disabled** (hover tooltip: collision warning) | Enabled |
| Split, no git, init checked, name empty | Disabled | Enabled |
| Split, git, name empty | Disabled | Disabled |

## Action Dispatch (`confirmNewSessionDialog`)

Single dispatcher inspects form state:
1. **No git ops needed** → open session as-is (new session) or no-op (split)
2. **initGit only** (no branch/worktree) → `WorktreeService.initGitRepo()` → open session
3. **gitMode == .branch + createBranch** → `confirmBranchCreation()` → `WorktreeService.createBranch()` → open session
4. **gitMode == .worktree** → `confirmWorktreeSplit()` → optionally `initGitRepo()` + `WorktreeService.createWorktree()` → open session/split

For **git init flows** (no-git + initGit checked): `initGitRepo()` creates an initial empty commit, which provides the `main` branch needed as base for branch/worktree creation.

## Info Tooltips

All options have `Image(systemName: "info.circle").help("...")`:
- **Initialize git**: "Creates a git repository in this folder with an initial commit."
- **Create branch**: "Creates a new git branch for this session."
- **Create new branch** (git flow): "Check to start work on a new branch instead of the current one."
- **Fork session**: "Preserves conversation history from the current session into the new one."
- **Initialize submodules**: Explains worktree submodule behavior.
- **Symlink build artifacts**: Explains build artifact symlinking.
- **Start (disabled)**: "Running two sessions on the same folder without git causes file collisions."

## Key Files

| File | Role |
|------|------|
| `Tenvy/Features/Git/NewSessionDialogView.swift` | The unified dialog view |
| `Tenvy/App/ContentViewModel.swift` | `PendingSplitRequest`, `WorktreeSplitFormData`, all action methods |
| `Tenvy/App/ContentView.swift` | Renders `NewSessionDialogView` when `pendingSplit != nil` |
| `Tenvy/Features/Git/WorktreeService.swift` | `createWorktree()`, `createBranch()`, `initGitRepo()`, `findRepoRoot()` |
| `Tenvy/Features/Git/GitBranchService.swift` | `currentBranch()`, `listLocalBranches()` (filesystem-based, no subprocess) |
