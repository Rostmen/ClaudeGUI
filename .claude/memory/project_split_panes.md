---
name: Split Pane Architecture
description: Tree-based split layout, pane headers with drag-to-rearrange, focus routing fix, PaneSplitTree/PaneSplitView implementation
type: project
---

# Split Pane Architecture

Tree-based split pane layout modelled after Ghostty's native split behaviour. Splitting a pane only divides that specific pane; all other panes are unaffected.

**Why:** The old flat `splitPanes: [ClaudeSession]` model split all panes equally. The new tree model mirrors how Ghostty handles splits internally.

**How to apply:** When changing split behaviour, the tree is in `PaneSplitTree` (recursive binary tree). `ContentViewModel.splitTree` owns it. `PaneSplitTreeRenderer` in `ContentView.swift` renders it recursively.

## Key Files

- `Tenvy/Features/Session/PaneSplitTree.swift` — `indirect enum Node { case leaf(ClaudeSession); case split(Split) }`. `Split` has `UUID id`, `SplitViewDirection`, `ratio: Double`, `left/right: Node`.
- `Tenvy/Features/Terminal/PaneSplitView.swift` — SwiftUI two-pane view with `GeometryReader + ZStack + offset` (NOT NSSplitView). Draggable divider.
- `ContentViewModel.splitTree: PaneSplitTree?` — nil = single-pane mode.
- `PaneSplitTreeRenderer` (private in ContentView) — recursively renders the tree.

## Ghostty Focus Bug Fix (paste routing)

**Root cause:** Ghostty's `SurfaceView` defaults `focused = true`. When SwiftUI recreates a non-selected pane's NSView (e.g., when transitioning from single-pane to split mode), the new surface keeps `focused = true`. `performKeyEquivalent` traverses ALL subviews — if the non-selected pane's surface is reached first with `focused = true`, it intercepts Cmd+V (paste) and other key equivalents.

**Fix:** In `GhosttyHostView.setup()`, after `addSubview(surfaceView)`, call:
```swift
_ = surfaceView.resignFirstResponder()
```
This sets `focused = false` on every new surface. Focus is granted only via `makeFocused()` → `window.makeFirstResponder(surfaceView)` → `becomeFirstResponder()` → `focusDidChange(true)`.

**Why the guard matters:** `focusDidChange` has `guard self.focused != focused else { return }`. Without the explicit resign, `focused = true` by default → `becomeFirstResponder` → `focusDidChange(true)` → guard short-circuits → `ghostty_surface_set_focus` NOT called.

## Focus Transfer Mechanism

- `pendingFocus: Bool` on `GhosttyHostView`: set in `makeNSView` when `isSelected = true`, consumed in `viewDidMoveToWindow`.
- **IMPORTANT**: `pendingFocus` must call `makeFocused()` via `DispatchQueue.main.async` (deferred one tick), NOT synchronously. Ghostty's `SurfaceView.viewDidMoveToWindow` fires after the host view's and resets internal focus state. Synchronous call races with it and loses.
- `GhosttyEmbedSurface.makeFocused()`: `resignFirstResponder()` + `window.makeFirstResponder(surfaceView)`.
- `DraggableTerminalView` (SwiftTerm): KVO on `window.firstResponder` → `onFocusGained` callback → `handleFocusGained(for:)`.
- `GhosttyHostView`: same KVO pattern.

## GhosttyHostView Cache (process survival on split)

**Problem:** SwiftUI destroys+recreates `NSViewRepresentable`-backed views when they move to a different structural position in the view tree (e.g. single-pane → first split). This kills the Ghostty process.

**Fix:** `ContentViewModel` holds a strong `@ObservationIgnored private var ghosttyHostViews: [String: GhosttyHostView]` cache keyed by `session.tenvySessionId`.

- `GhosttyTerminalView` takes `existingHostView: GhosttyHostView?` and `onHostViewCreated: ((GhosttyHostView) -> Void)?`.
- `makeNSView` returns the cached view unchanged if `existingHostView != nil` (skips `setup()`, process never restarts).
- `onHostViewCreated` fires for fresh views so callers can populate the cache.
- Cache evicted in `closeSplitPane(id:)` and `closeSplit()` — ensures the process terminates when the pane is explicitly closed.
- `TerminalView` (SwiftUI wrapper) passes these through; SwiftTerm ignores them (nil defaults).

## Pane Headers & Drag-to-Rearrange

Every pane has a `PaneHeaderView` (always visible, single or split mode): 30px height, title left, IDE button + close button right. Files are in `Tenvy/Features/Terminal/PaneHeader/` folder (split from the original monolithic file).

**Drag**: `PaneHeaderDragSourceNSView` (in `PaneHeaderDragSource.swift`, AppKit NSDraggingSource) encodes `tenvySessionId` on pasteboard as `com.tenvy.paneId` UTType. 20%-scaled terminal snapshot as drag image. Follows Ghostty's `SurfaceDragSourceView` pattern. Trailing inset is dynamic — expands when IDE button is present to pass through clicks to SwiftUI.

**Drop**: `PaneDropDelegate` (SwiftUI DropDelegate) on each `PaneLeafView`. `PaneDropZone` (ported from Ghostty's `TerminalSplitDropZone`) determines split direction via triangular edge detection.

**Move**: `PaneSplitTree.moving(sessionId:toDestination:direction:)` — remove source, insert at destination. Matches Ghostty's `splitDidDrop`.

**Title**: Claude sessions → `session.title`; plain terminals → `GhosttyEmbedSurface.title` (auto-updates from escape sequences).

**Cross-window**: Pasteboard uses string tenvySessionId. `Notification.paneDragEndedNoTarget` posted when drag ends outside windows — ready for future cross-window transfer.
