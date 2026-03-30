---
name: No overlay hacks on SwiftUI List rows
description: Never overlay NSViews on SwiftUI List rows with hitTest/sendEvent workarounds — use dedicated AppKit subviews instead
type: feedback
---

Never overlay a full-row NSView on SwiftUI List rows to intercept mouse events. Hacks like `hitTest` toggling, `window?.sendEvent()` re-dispatch, local event loops (`window?.nextEvent`), and `NSEvent.addLocalMonitorForEvents` with invisible views all fail in different ways (unresponsive UI, recursive crashes, broken selection).

**Why:** SwiftUI's `List(selection:)` needs to receive `mouseDown` for selection. An overlay intercepts it first, and no re-dispatch mechanism reliably forwards it back.

**How to apply:** When AppKit functionality is needed inside a SwiftUI List row (e.g., `NSDraggingSource`), use a small dedicated NSView (like a drag handle icon) that doesn't conflict with the rest of the row's SwiftUI interaction.
