# Ghostty Integration Findings

## Context Menu

SwiftUI `.contextMenu { }` does NOT work on terminal views. Ghostty's `SurfaceView` (NSView) overrides `menu(for:)` and intercepts right-clicks at the AppKit level before SwiftUI sees them.

**Solution**: `GhosttyHostView` installs `NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown)` to intercept before Ghostty. The host exposes `contextMenuProvider: (() -> NSMenu)?` — each owning view provides its own menu. Menu action targets stored on `hostView.menuTarget` (strong property) to stay alive while menu is open.

Approaches that DO NOT work:
- SwiftUI `.contextMenu { }` on the NSViewRepresentable
- `willOpenMenu(_:with:)` override on GhosttyHostView (fires on parent, not on the subview that owns the menu)
- NSMenuDelegate on the surface's menu (menu is recreated each time via `menu(for:)`)

## SIGCHLD Deadlock

Ghostty installs a SIGCHLD handler that reaps all child processes. Spawning subprocesses via `Process()` / `ps` while Ghostty is active causes deadlock — `waitUntilExit()` never returns because Ghostty's handler reaps the child first.

**Solution**: Use `sysctl(KERN_PROC_ALL)` for process enumeration (no subprocess). Git operations (`git worktree add`, `git init`) via `Process()` are safe because they run BEFORE the Ghostty surface is created for that pane.

## Branch Detection

Read `.git/HEAD` directly from filesystem — no subprocess needed. For worktree git dirs, resolve `commondir` to find the main repo's `refs/heads/`. `GitBranchService.listLocalBranches(at:)` enumerates `refs/heads/` + parses `packed-refs`.

## Terminal Reset

Ghostty's "Reset Terminal" context menu action sends `ghostty_surface_binding_action(surface, "reset")` — a terminal emulator reset (clears screen, resets escape state). Safe for plain shells (prompt reappears). For Claude TUI sessions, the screen blanks with no auto-recovery — that's why `ClaudeSessionTerminalView` excludes Reset from its context menu.

## Focus Management

Ghostty `SurfaceView` defaults `focused = true`. Must call `resignFirstResponder()` immediately after `addSubview` to prevent non-selected panes from intercepting `performKeyEquivalent` (paste, shortcuts). Focus granted only via `makeFocused()`.

## Process Identity

`ghostty_surface_foreground_pid` returns the PTY foreground PID. Since launch scripts use `exec claude`, the shell is replaced at the same PID. `shellPid` is always 0 with Ghostty (it manages its own PTY).
