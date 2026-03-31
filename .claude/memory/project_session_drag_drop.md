---
name: Session Drag & Drop
description: Pane header drag-and-drop for rearranging splits, cross-window transfer, outside-window detection
type: project
---

## Overview

Pane headers (not sidebar) provide drag-and-drop for rearranging split panes and moving sessions between windows. The sidebar no longer has drag handles — all drag originates from the pane header bar.

## Architecture

### Drag Source: `PaneHeaderDragSourceNSView`

AppKit `NSDraggingSource` covering the entire header bar. Encodes `terminalId` (String) on the pasteboard using `com.tenvy.paneId` UTType. Creates a 20%-scaled terminal snapshot as drag preview.

- Escape key cancels the drag
- Open/closed hand cursor during hover/drag
- `draggingSession(_:endedAt:operation:)` detects drops outside windows and posts `Notification.paneDragEndedNoTarget`

### Drop Target: `PaneDropDelegate`

SwiftUI `DropDelegate` on each `PaneLeafView`. Uses `PaneDropZone` (ported from Ghostty's `TerminalSplitDropZone`) for triangular edge detection — cursor's nearest edge determines split direction.

### Move Operation

**Same-window:** `PaneSplitTree.moving(sessionId:toDestination:direction:)` — remove source, insert at destination.

**Cross-window:** `movePaneToSplit` detects the source isn't local, calls `appModel.releaseSessionForTransfer` on the source window, then `receiveTransferredSession` with the correct drop zone direction.

### Cross-Window Transfer Infrastructure

Sessions move between windows without restarting the terminal process:

1. **AppModel** holds `hostViewTransfers: [String: GhosttyHostView]` temporary store and weak `registeredViewModels` registry
2. Source ViewModel calls `prepareForTransfer(sessionId:)` → extracts host view (without closing), deposits on AppModel, removes from split tree
3. Destination ViewModel calls `receiveTransferredSession(_:alongside:direction:)` → picks up host view, inserts into split tree
4. `ghosttyHostView(for:)` auto-checks AppModel's transfer store — new windows seamlessly pick up transferred views

### Drag Outside Window

`ContentViewModel` observes `paneDragEndedNoTarget` notification. When a pane header is dragged outside all windows, `handlePaneDragToNewWindow` finds the session by terminalId and calls `handleDragToNewWindow` to open it in a new tab.

### SessionListAction Enum

Sidebar actions (no drag cases — drag is handled by pane headers):

```swift
enum SessionListAction {
  case select(ClaudeSession)
  case createNew(ClaudeSession)
  case openInNewWindow(ClaudeSession)
  case moveToNewWindow(ClaudeSession)
}
```

## Key Files

| File | Role |
|------|------|
| `PaneHeaderView.swift` | Header bar with `PaneHeaderDragSourceNSView` (NSDraggingSource) |
| `PaneDropZone.swift` | Triangular edge detection + overlay (ported from Ghostty) |
| `ContentView.swift` | `PaneLeafView` (header + terminal + drop zone), `PaneDropDelegate` |
| `ContentViewModel.swift` | `movePaneToSplit`, transfer methods, notification observer |
| `AppModel.swift` | Transfer store, ViewModel registry, `releaseSessionForTransfer` |
