---
name: Use action enums instead of callback closures
description: Prefer enum-based action handlers over multiple callback closure parameters in views and host views
type: feedback
---

Use action enums instead of multiple `on*` callback closures in views.

**Why:** Multiple closure parameters (`onStateChange`, `onFocusGained`, `onShellStart`, etc.) create noisy call sites and make it hard to see what a view communicates. A single `onAction: (Action) -> Void` handler is cleaner and self-documenting.

**How to apply:**
- Define an `Action` enum with documented cases for each event the view can emit
- Views expose `let onAction: (Action) -> Void` (or optional if the view can work without it)
- ViewModels handle with `func handle(action:)` using a switch
- Structural/lifecycle params (`existingHostView`, `onHostViewCreated`) stay as separate params — they're configuration, not actions
