---
name: Context menu architecture for embedded Ghostty terminals
description: Why SwiftUI .contextMenu doesn't work, how right-click interception works, view-owned menus
type: project
---

SwiftUI `.contextMenu { }` does NOT work on terminal views because Ghostty's `SurfaceView` (an NSView subview inside NSViewRepresentable) overrides `menu(for:)` and intercepts right-clicks at the AppKit level before SwiftUI sees them.

**Why:** AppKit asks the frontmost NSView under the cursor for its menu. The SurfaceView is that view, not the SwiftUI wrapper. SwiftUI's contextMenu modifier only works when SwiftUI handles hit-testing.

**How to apply:**
- `GhosttyHostView` installs `NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown)` to intercept right-clicks before Ghostty's `menu(for:)` runs
- Host exposes `contextMenuProvider: (() -> NSMenu)?` — a hook for the owning view
- Each view (`ClaudeSessionTerminalView`, `PlainTerminalView`) sets this provider to build its own menu
- Menu action targets are stored on `hostView.menuTarget` (strong property) to keep them alive while the menu is open
- This is the ONLY way to customize the context menu — `willOpenMenu`, subclassing SurfaceView, or NSMenuDelegate do not work
