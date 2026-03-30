---
name: Terminal Backend (Ghostty only)
description: SwiftTerm was removed; Ghostty (GhosttyTerminalView) is the sole terminal backend
type: project
---

# Terminal Backend

Ghostty is the only terminal backend. SwiftTerm has been fully removed.

**Why:** SwiftTerm was the original default with Ghostty as an "experimental" alternative. Once Ghostty was stable and all parity code was in place, SwiftTerm was deprecated and removed to simplify the codebase.

**How to apply:** Do not suggest adding SwiftTerm back or creating backend-agnostic abstractions. `GhosttyTerminalView` is used directly in `ContentView` — there is no `TerminalView` wrapper struct anymore.

## What was removed

- `TerminalType.swift` — enum deleted entirely
- `AppSettings.terminalType` — property removed
- Settings terminal picker — removed from `SettingsView`
- `TerminalView` struct — the SwiftUI switch wrapper, removed
- `TerminalContentView` struct — SwiftTerm NSViewRepresentable, removed
- `DraggableTerminalView` class — LocalProcessTerminalView subclass, removed
- `ClaudeTerminalColors` enum — SwiftTerm ANSI palette, removed
- `import SwiftTerm` — removed from all files
- SwiftTerm package dependency — must be removed from Xcode (File → Packages)

## What remains in TerminalView.swift

The file is kept but now only contains shared types used by `GhosttyTerminalView`:
- `SplitDirection` enum
- `SessionMonitorInfo` struct
- `SessionStateMonitor` class
