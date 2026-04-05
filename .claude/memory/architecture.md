# Architecture Decisions

## Terminal View Three-Layer Separation

Terminal views are split into three layers:

- **`GhosttyHostView`** (NSView): generic host — surface lifecycle, focus, layout, optional process monitoring. Does NOT know about Claude sessions or plain terminals.
- **`ClaudeSessionTerminalView`** (NSViewRepresentable): Claude Code sessions — builds CLI command, monitoring, session-specific context menu.
- **`PlainTerminalView`** (NSViewRepresentable): plain login shell — no monitoring, no session tracking, terminal-specific context menu.

The host provides composable building blocks (`setupSurface`, `setupMonitoring`). Each view decides what to call.

## Worktree Split Panes

Split requests are intercepted to show a worktree dialog:
- **Git repos**: branch picker, new branch name, worktree destination, fork session toggle
- **Non-git dirs**: "Initialize Git & Create Worktree" or "Open Plain Terminal"

Worktree creation uses `git worktree add` via `Process()` — safe because it runs before Ghostty surface creation. Default destination: `<repo>/.claude/worktrees/<branch>/` (matches Claude CLI convention).

Fork session: `claude --resume <session-id> --fork-session` — creates new session preserving conversation history.

## GhosttyHostView Cache

SwiftUI destroys NSViewRepresentable views when they move in the view tree (e.g., single → split). `ContentViewModel` holds `[String: GhosttyHostView]` cache keyed by `tenvySessionId`. Cached views bypass `setup()` — process survives restructuring.

## Preview Infrastructure

`TenvyApp` detects preview sandbox via `XCODE_RUNNING_FOR_PLAYGROUNDS=1` and renders `Color.clear` instead of `ContentView`. Without this, the full app's `NavigationSplitView` + `List` with `Section(isExpanded:)` crashes the preview process (`OutlineListCoordinator` assertion failure).
