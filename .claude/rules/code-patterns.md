---
description: Coding patterns and conventions for Tenvy SwiftUI/AppKit codebase
---

# Code Patterns

## Action enums over callback closures

Use action enums instead of multiple `on*` callback closures in views:

```swift
enum Action {
  /// Description of what this action does
  case someAction(param: Type)
}

// In views:
let onAction: (Action) -> Void

// In ViewModels:
func handle(action: Action) {
  switch action { ... }
}
```

Structural/lifecycle params (`existingHostView`, `onHostViewCreated`) stay as separate params — they're configuration, not actions.

## Separation of concerns

Views should know as little about each other as possible. When a parent hosts a child:
- The child decides its own behavior (e.g., what context menu to show)
- The parent provides generic hooks (e.g., `contextMenuProvider`) not specific knowledge
- Communication uses abstract types (enums, closures) not direct references
- Avoid boolean flags like `isPlainTerminal` — use more general properties (e.g., `sessionName: String`) or separate types entirely

## Avoid unnecessary optionals

If a parameter is always provided at call sites, make it non-optional. Use default values (e.g., `var onAction: (Action) -> Void = { _ in }`) instead of optionals when a no-op default makes sense.

## No ObjC runtime hacks

Avoid `objc_setAssociatedObject` and similar tricks. Use regular stored properties instead. If an object needs to stay alive, store it as a property on the owner.
