---
name: Persistent Session Store (GRDB)
description: GRDB-backed SQLite database for session state — replaces fragile in-memory sync with DB-backed source of truth
type: project
---

Sessions are stored in `~/Library/Application Support/Tenvy/sessions.sqlite` via GRDB + GRDBQuery.

## Architecture

- **SessionRecord** (GRDB model): `tenvySessionId` (PK), `claudeSessionId`, `workingDirectory`, `projectPath`, `title`, `hookState`, `currentTool`, `branchName`, `worktreePath`, `isPlainTerminal`, `isActive`, etc.
- **SessionStore**: sole DB write service. Views never call it — only ViewModels and services do.
- **@Query**: views observe the DB via GRDBQuery's `@Query` property wrapper for reactive updates.
- **SessionRuntimeInfo**: stays in-memory for CPU/memory/PID (too chatty for DB).

## Session ID Mapping

`TENVY_SESSION_ID` env var is set before launching Claude. The hook script includes it as `terminal_id` in JSONL events. When `HookEventService` receives an event with both `session_id` and `terminal_id`, `SessionStore.updateHookState()` writes the mapping to DB.

**Why:** Replaces the old fragile `syncNewSessionWithDiscoveredSession()` / `syncSplitSession()` which matched by `workingDirectory` + `lastModified` — caused cross-pane state leakage and plain terminals stealing Claude session IDs.

## Write Discipline

1. Views → Action enum → ViewModel → `SessionStore`
2. Services → `AppModel.wireCallbacks()` → `SessionStore`
3. `SessionManager` → `SessionStore.upsertFromSessionFile()`

## Key Files

- `Tenvy/Core/AppDatabase.swift` — DatabasePool, migrations
- `Tenvy/Core/SessionRecord.swift` — model + query request types
- `Tenvy/Core/SessionStore.swift` — write service
- `Tenvy/Features/Terminal/TerminalEnvironment.swift` — sets `TENVY_SESSION_ID`
- `Hooks/chat-sessions-hook.sh` — includes `terminal_id` in events

**How to apply:** When adding new session state that should be persistent and observable across views, add a column to `SessionRecord` (with migration), a write method to `SessionStore`, and use `@Query` in views. Keep ephemeral per-process data (CPU, PID) in `SessionRuntimeInfo`.
