---
name: Session Drag & Drop
description: Sidebar drag-and-drop for active sessions — drag handle, cross-window transfer, outside-window detection, action enum refactor
type: project
---

## Overview

Active sessions in the sidebar can be dragged to merge into split panes or moved to new windows. The implementation uses a dedicated AppKit drag handle (not a SwiftUI overlay) to avoid conflicts with SwiftUI List selection.

## Architecture

### Drag Handle: `SessionDragHandle` / `SessionDragHandleView`

A 16×16 `NSViewRepresentable` placed at the trailing top of each active session row (inline with the title). Uses `hand.tap` SF Symbol via a `PassthroughImageView` (NSImageView subclass with `hitTest` returning nil so mouse events reach the parent).

**Why AppKit, not SwiftUI?** SwiftUI's `.draggable()` provides no callback when a drag ends. `NSDraggingSource.draggingSession(_:endedAt:operation:)` is the only way to detect drops outside the window.

**Why a small icon, not a full-row overlay?** The sidebar is a SwiftUI `List(selection:)`. An NSView overlay over the entire row intercepts `mouseDown` before the List, breaking click-to-select. A dedicated drag handle avoids the conflict entirely: click the handle → drag, click elsewhere → select.

**Failed approaches (do NOT retry):**
1. Full-row NSView overlay with `hitTest` toggling + `window?.sendEvent()` re-dispatch → caused sidebar to become unresponsive, recursive crashes
2. `NSEvent.addLocalMonitorForEvents` with `hitTest` returning nil → `beginDraggingSession` failed on invisible views
3. Local event loop in `mouseDown` (`window?.nextEvent(matching:)`) → blocked the run loop

### Cross-Window Transfer

Sessions can be moved between windows without restarting the terminal process:

1. **AppModel** holds a `hostViewTransfers: [String: GhosttyHostView]` temporary store and a weak `registeredViewModels` registry
2. Source ViewModel calls `prepareForTransfer(sessionId:)` → extracts host view from cache (without closing!), deposits on AppModel, removes from split tree
3. Destination ViewModel calls `receiveTransferredSession(_:alongside:)` → picks up host view, inserts into split tree
4. `ghosttyHostView(for:)` auto-checks AppModel's transfer store — new windows seamlessly pick up transferred host views

**Cross-window routing:** `handleDropSession` checks if the target session is in this window. If not, delegates via `appModel.mergeTransferredSession()` which finds the correct ViewModel through the registry.

**Empty window cleanup:** `prepareForTransfer` closes the window after releasing its last session (unless it's the only visible window).

### Pasteboard Format

Uses `String.pasteboardItem()` from GhosttyEmbed's `Transferable+Extension.swift` (made `public`). This goes through the same `Transferable` pipeline as SwiftUI's `.dropDestination(for: String.self)`, guaranteeing byte-level format compatibility.

### Drop Targets

- **Session rows:** `.dropDestination(for: String.self)` — dropping a session merges into split (with accent border highlight on hover)
- **"New Window" drop zone:** Row at the bottom of active sessions section
- **Outside window:** Detected by `draggingSession(_:endedAt:operation:)` when `operation == []` and point is outside all visible windows. Escape key cancels without triggering.

### SessionListAction Enum

All sidebar callbacks consolidated into one enum (replaced 6 separate closures):

```swift
enum SessionListAction {
  case select(ClaudeSession)
  case createNew(ClaudeSession)
  case openInNewWindow(ClaudeSession)
  case moveToNewWindow(ClaudeSession)
  case dropOntoSession(droppedSessionId: String, targetSessionId: String)
  case dragToNewWindow(sessionId: String)
}
```

Flows: `SessionListView` → `SidebarView` → `ContentView` → `ContentViewModel.handleSessionListAction(_:)`

### GhosttyHostView Close (BAD_ACCESS fix)

`evictGhosttyHostView` calls `hostView.close()` before dealloc. `close()` removes the surface NSView from the hierarchy, stops monitoring, removes event monitors. The host view is kept alive for one extra run-loop tick via `DispatchQueue.main.async` so `ghostty_surface_free` (scheduled in `Surface.deinit` via `Task.detached`) completes before the `SurfaceView` deallocates.

## Key Files

| File | Role |
|------|------|
| `SessionDragSource.swift` | `SessionDragHandle` + `SessionDragHandleView` (NSDraggingSource) + `PassthroughImageView` |
| `SessionListView.swift` | `SessionListAction` enum, drop targets, "New Window" zone |
| `SessionRowView.swift` | Drag handle placement (trailing top, inline with title) |
| `ContentViewModel.swift` | `handleSessionListAction`, transfer methods, `prepareForTransfer`, `receiveTransferredSession` |
| `AppModel.swift` | Transfer store, ViewModel registry, `releaseSessionForTransfer`, `mergeTransferredSession` |
| `GhosttyHostView.swift` | `close()` method for safe surface teardown |
| `Transferable+Extension.swift` | `pasteboardItem()` made public for cross-module use |
