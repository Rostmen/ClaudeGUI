# Memory Index

## Project
- [project_tenvy.md](project_tenvy.md) — What Tenvy is, repo, bundle ID, team ID, why no App Store
- [project_github_actions.md](project_github_actions.md) — CI release workflow, signing approach, required secrets, known gotchas
- [project_hooks.md](project_hooks.md) — Claude Code hook events, state mapping, permission responses
- [project_notifications.md](project_notifications.md) — macOS notifications implementation, key decisions, dedup guard behaviour
- [project_terminal_env.md](project_terminal_env.md) — Shell sourcing, LANG fix, custom env vars in Settings
- [project_updates.md](project_updates.md) — Update checker, silent brew install, isUpdating flag, release notes window
- [project_appearance.md](project_appearance.md) — Light/Dark/System setting, ClaudeThemeSync, auto-restart idle sessions, Ghostty login-shell fix
- [project_split_panes.md](project_split_panes.md) — Tree-based split layout, Ghostty paste focus bug fix, PaneSplitTree/PaneSplitView, focus transfer mechanism
- [project_terminal_backend.md](project_terminal_backend.md) — SwiftTerm removed; Ghostty is the sole backend; what was deleted
- [project_process_monitoring.md](project_process_monitoring.md) — sysctl replaces ps; Ghostty SIGCHLD deadlock; PID discovery and kill target logic
- [project_terminal_views.md](project_terminal_views.md) — Three-layer terminal architecture: ClaudeSessionTerminalView / PlainTerminalView / GhosttyHostView
- [project_context_menu.md](project_context_menu.md) — Why SwiftUI .contextMenu fails on Ghostty; right-click interception; view-owned menus
- [project_session_drag_drop.md](project_session_drag_drop.md) — Sidebar drag-and-drop: drag handle, cross-window transfer, outside-window detection, SessionListAction enum
- [project_new_session_flow.md](project_new_session_flow.md) — "+" button flow: folder picker, git detection, dialog, tab/window routing
- [project_new_session_dialog.md](project_new_session_dialog.md) — Unified NewSessionDialogView: all git/no-git scenarios, progressive disclosure, branch/worktree modes

## Feedback
- [feedback_commits.md](feedback_commits.md) — Never commit/push without explicit user approval
- [feedback_action_enums.md](feedback_action_enums.md) — Use action enums instead of multiple callback closures in views
- [feedback_document_architecture.md](feedback_document_architecture.md) — Always update CLAUDE.md and memory on architecture changes
- [feedback_no_overlay_hacks.md](feedback_no_overlay_hacks.md) — Never overlay NSViews on SwiftUI List rows; use dedicated AppKit subviews
- [feedback_pr_docs_audit.md](feedback_pr_docs_audit.md) — Before any PR, audit all memory/docs for outdated or missing coverage
