---
name: Terminal view architecture — three-layer separation
description: ClaudeSessionTerminalView / PlainTerminalView / GhosttyHostView separation of concerns
type: project
---

Terminal views are split into three layers with clear separation of concerns:

**`GhosttyHostView`** (NSView) — generic terminal host, knows nothing about Claude or plain shells:
- Surface lifecycle (create, resize, focus, layout)
- Process monitoring (optional — only when `setupMonitoring` is called)
- Right-click interception → delegates to `contextMenuProvider`
- Upstream events via `onAction: (TerminalAction) -> Void`

**`ClaudeSessionTerminalView`** (NSViewRepresentable) — Claude Code sessions:
- Builds Claude CLI command (path resolution, `--resume`, `--fork-session`)
- Calls both `setupSurface` and `setupMonitoring` on the host
- Owns its context menu: Copy, Paste, Splits, Rename Session, Close Session
- No Reset Terminal (breaks Claude's TUI display — screen blanks with no recovery)

**`PlainTerminalView`** (NSViewRepresentable) — plain login shell:
- Builds shell command via `TerminalEnvironment.plainShellArgs`
- Calls only `setupSurface` on the host (no monitoring, no session tracking)
- Owns its context menu: Copy, Paste, Splits, Reset Terminal, Rename Terminal, Close Terminal

**Why this split:** Each view knows its own concerns (what to launch, what menu to show). The host view is reusable and doesn't need boolean flags or mode switches. Context menus are entirely owned by the views — the host just provides the right-click hook.
