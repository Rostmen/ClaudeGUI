---
name: File drag & drop into terminal
description: Dual-path file drop implementation — AppKit for split mode, SwiftUI fallback for single-pane; header highlight and focus-on-drop
type: project
---

# File Drag & Drop into Terminal

## Problem

SwiftUI's hosting layer blocks AppKit drag events from reaching child NSViews in single-pane mode. Ghostty's `SurfaceView` registers for `.fileURL`/`.URL`/`.string` drag types, but the drag never reaches it when the terminal is the only view in a `NavigationSplitView` detail wrapped with `.allowsHitTesting()` and `.opacity()` modifiers.

In split mode (via `PaneSplitView` with `.frame().offset()` positioning), the same AppKit drag events DO reach child NSViews.

## Solution: Dual-Path Architecture

### Split mode — AppKit level (GhosttyHostView)

1. `setupSurface()` calls `surfaceView.unregisterDraggedTypes()` to remove SurfaceView's registration
2. `GhosttyHostView` registers itself for `[.string, .fileURL, .URL]`
3. Overrides `draggingEntered` → fires `TerminalAction.fileDragEntered`
4. Overrides `draggingExited` → fires `TerminalAction.fileDragExited`
5. Overrides `performDragOperation` → shell-escapes paths, calls `surface.sendText()`, fires `.fileDropped`
6. `PaneLeafView.handleAction()` routes these to `viewModel.fileDropTargetTerminalId` (highlight) and `viewModel.focusPane()` (focus)

### Single-pane mode — SwiftUI fallback (DetailView)

1. `.onDrop(of: [.fileURL], isTargeted: $isSinglePaneDropTargeted)` applied AFTER `.allowsHitTesting()` in the modifier chain
2. `onChange(of: isSinglePaneDropTargeted)` syncs to `viewModel.fileDropTargetTerminalId`
3. Drop handler calls `viewModel.handleSinglePaneFileDrop()` → loads URLs from `NSItemProvider`, shell-escapes, sends via `surface.sendText()`

### Unified highlight state

`ContentViewModel.fileDropTargetTerminalId: String?` is the single source of truth:
- Set by AppKit `onAction(.fileDragEntered)` callbacks in split mode
- Set by SwiftUI `isTargeted` binding + `onChange` in single-pane mode
- Read by `PaneLeafView.isFileDropTargeted` computed property → passed to `PaneHeaderView.isFileDropTarget`
- `PaneHeaderView` shows pulsing accent-color background + accent border when targeted

## Key Constraint

**Why not just use SwiftUI `.onDrop` everywhere?** In split mode, per-pane `.onDrop(of: [.fileURL])` handlers on `PaneLeafView`'s inner views don't fire — the AppKit-level drag destination (GhosttyHostView/SurfaceView) processes the drag before SwiftUI sees it. Conversely, in single-pane mode, SwiftUI intercepts before AppKit. Neither approach works alone for both modes.

## Shell Escaping

`GhosttyHostView.shellEscape()` mirrors Ghostty's internal `Shell.escape()`. Escapes: `\ ()[]{}<>"'`!#$&;|*?\t`. Made `static` so `ContentViewModel` can call it for the single-pane path.
