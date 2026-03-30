---
name: Worktree Dialog System
description: How the worktree creation dialog works — PendingSplitRequest, WorktreeSplitFormData, dual-mode (split vs new session), ContentView overlay
type: project
---

# Worktree Dialog System

A modal dialog for creating git worktrees, shared between two flows: split panes (context menu) and new sessions ("+" button).

## Trigger Points

1. **Split from context menu**: `TerminalAction.splitRequested(direction:)` → `handleSplitRequested()` — checks `runtimeInfo.gitBranch != nil`
2. **New session from "+"**: `createNewSession()` → checks `WorktreeService.findRepoRoot(from: path)`

Both set `pendingSplit` and (if git) `worktreeSplitForm`, which triggers the dialog overlay in `ContentView`.

## Data Model

```swift
struct PendingSplitRequest {
  let direction: SplitDirection       // .right/.left/.up/.down (ignored in new session flow)
  let sourceSession: ClaudeSession    // the session/folder the dialog was triggered from
  let hasGitRepo: Bool                // true → WorktreeSplitView, false → NoGitSplitView
  let isNewSessionFlow: Bool          // true = "+" button, false = context menu split
}

struct WorktreeSplitFormData {
  var baseBranch: String              // branch to fork from
  var newBranchName: String           // auto-generated: "MM-dd-yyyy-HH-mm-session-title"
  var worktreePath: String            // auto-updated from defaultWorktreePath when branch name changes
  var forkSession: Bool               // copy conversation history (split flow only, hidden for new sessions)
  var availableBranches: [String]     // from GitBranchService.listLocalBranches
  let sourceSessionId: String
  let sourceIsNewSession: Bool        // controls fork toggle visibility
  let repoRoot: String               // from WorktreeService.findRepoRoot
}
```

## Dialog Display (ContentView)

```swift
if viewModel.pendingSplit != nil {
  // Dimmed backdrop, tap to cancel
  if pendingSplit.hasGitRepo == true → WorktreeSplitView
  else → NoGitSplitView
}
```

## WorktreeSplitView Adaptations

The view reads `viewModel.pendingSplit?.isNewSessionFlow` to adapt:
- **Header**: "New Session in Worktree" vs "Create Worktree Split"
- **Skip button**: "Skip" (proceeds without worktree) vs "Plain Terminal" (opens shell split)
- **Fork toggle**: hidden when `sourceIsNewSession == true` (always true for new session flow)

## Confirmation Flow

`confirmWorktreeSplit()`:
1. Calls `WorktreeService.createWorktree(repoPath:newBranch:baseBranch:destinationPath:)`
2. If `isNewSessionFlow`: creates `ClaudeSession` at worktree path → `activateNewSession()`
3. If split flow: `performSplitWithWorktree()` → `insertSplitPane()`
4. `dismissSplitDialog()` clears all dialog state

`openPlainTerminalSplit()` (skip/plain terminal):
- New session flow: `activateNewSession(pending.sourceSession)` at original path
- Split flow: creates plain terminal session → `insertSplitPane()`

## Dismissal

`dismissSplitDialog()` clears: `pendingSplit`, `worktreeSplitForm`, `worktreeError`, `isCreatingWorktree`

## Key Files

- `ContentViewModel.swift` — `PendingSplitRequest`, `WorktreeSplitFormData`, `handleSplitRequested()`, `confirmWorktreeSplit()`, `openPlainTerminalSplit()`, `dismissSplitDialog()`
- `WorktreeSplitView.swift` — git repo dialog (branch picker, path, fork toggle, adaptive buttons)
- `NoGitSplitView.swift` — non-git dialog (git init option, plain terminal)
- `ContentView.swift` — overlay rendering (lines ~154-167)
- `WorktreeService.swift` — `findRepoRoot()`, `createWorktree()`, `defaultWorktreePath()`, `initGitRepo()`
- `GitBranchService.swift` — `currentBranch(at:)`, `listLocalBranches(at:)` (filesystem-based, no subprocess)
