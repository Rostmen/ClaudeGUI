---
name: Inspector Panel
description: Right-side collapsible inspector panel — branch switcher, paths, SwiftUI .inspector() modifier, GitBranchService extensions
type: project
---

Collapsible right-side panel using SwiftUI `.inspector()` modifier on the `NavigationSplitView`. Divider extends through the navigation bar (Xcode-style).

## Toggle

- Toolbar button (`sidebar.trailing` icon) in `navigationContent`
- Menu: View > Toggle Inspector (⌘⌥I) via `Notification.toggleInspectorPanel`
- State: `ContentViewModel.showInspectorPanel`

## Content (InspectorPanelView)

Renders only when `selectedSession` is non-nil. Updates immediately on focus change.

### Branch Section

- `Picker` dropdown with current branch from `runtimeInfo.gitBranch`
- Lists all local branches via `GitBranchService.listLocalBranches(at:)`
- Excludes worktree-checked-out branches via `GitBranchService.worktreeBranches(at:)` (reads `.git/worktrees/*/HEAD`, no subprocess)
- On branch select: `GitBranchService.checkoutBranch(_:at:)` runs `git checkout`
- On failure: alert with git error message (e.g. uncommitted changes conflict)

### Paths Section

- Working directory and project path with `~` abbreviation
- Folder icon (fills on hover via `@State isHovered`) reveals in Finder via `NSWorkspace.shared.selectFile`

## GitBranchService Extensions

Two methods added for the inspector:
- `worktreeBranches(at:)` — reads `.git/worktrees/*/HEAD` to find worktree-checked-out branches (filesystem only)
- `checkoutBranch(_:at:)` — runs `git checkout <branch>`, returns error string on failure or nil on success
