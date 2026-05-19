# Scheduled Tasks — Design & Implementation Plan

> Status: **Approved design, ready for implementation.**
> Owner: Rostyslav.
> Last updated: 2026-05-18.
>
> **Amendment 2026-05-18 (worktree-optional)**: Decision #5 ("Worktree only") was revised. Tasks now carry a `useWorktree` flag (default OFF). When OFF, the run executes directly in the chosen folder with no git involvement; `customWorktreeBase`, `pendingGitInit`, and the branch/worktree pipeline are skipped. The git-init checkbox in the create form is only shown when worktree is enabled. Migration v6 adds the column and wipes pre-existing scheduled tasks (their worktree-always semantics don't carry over cleanly).

This document is the single source of truth for the Scheduled Tasks feature. It captures every product decision agreed during planning, the resulting data model, the runtime semantics, the UI surface, the edge cases, and the implementation order. Open it before writing any code in this feature; if you change a decision, change this file first.

---

## 1. Goal

Let a user define a **recurring Claude Code task** that fires on a fixed schedule (minutes / hours / days / weeks). Each firing spawns a fresh Claude session inside its own git worktree, pre-seeded with a user-provided prompt, and surfaced in a dedicated window. The whole lifecycle is supervised by Tenvy — no firing while the app is closed, no orphan windows, no overlapping runs.

## 2. Non-goals (v1)

- Manual "Run now" trigger. The schedule is the only execution source.
- Cron-style expressions. We expose a curated frequency picker only.
- Catching up missed runs after an app close. We skip them.
- Multiple concurrent windows per task. Strict one-at-a-time.
- Surfacing scheduled affiliation on session rows or in the inspector for spawned sessions. The drill-down sub-list is the only filter.
- A separate "Runs log" view. The sub-list shows only real sessions; skipped/failed runs only live in the task's "last run status" fields.
- Per-execution permission overrides. Permissions are set on the task and inherited by every run.

---

## 3. End-to-end product specification

### 3.1 Creation flow

Trigger: the sidebar's existing toolbar **+** button. Single click defaults to "New Session"; the attached dropdown menu also exposes **"New Scheduled Task"**.

Opens a dialog (`CreateScheduledTaskView`) with the following form:

| Field | Type | Notes |
|---|---|---|
| Name | TextField, required, 1–80 chars | Used for session titles, branch slugs, sidebar row. |
| Working folder | Folder picker (NSOpenPanel) | Required. The repo (or future repo) where executions run. |
| Git strategy | Read-only label, dynamic | If folder *is* a git repo: "Worktree (required)". If folder is *not* a git repo: "Git init + worktree" with an explicit "I understand, init git on first run" checkbox the user must check to enable Save. |
| Custom worktree base (optional) | TextField with browse button | If empty, falls back to `WorktreeService.defaultWorktreePath` for the timestamped branch. |
| Frequency unit | Picker: Minutes / Hours / Days / Weeks | Required. |
| Frequency value (N) | Stepper, 1–999 | Required. |
| Time of day | DatePicker, `.hourAndMinute` | Visible only for **Days** and **Weeks**. Required when visible. |
| Weekdays | Multi-select chip set (Mon–Sun) | Visible only for **Weeks**. At least one required. |
| Prompt input | Segmented control: **Text** / **File** | Required. |
| · Prompt text | Multi-line TextEditor (1–10k chars) | Visible when "Text". |
| · Prompt file | File path field + browse button | Visible when "File". File is **re-read** on every run; missing/unreadable → run fails. |
| Permissions | Embedded `PermissionEditorView` | Pre-filled by `ClaudeSettingsService.mergeForNewSession()` (same as regular new sessions). |

Save button:

1. Validates fields.
2. If folder is not git and "init git" checkbox is unchecked → save is disabled.
3. If folder is not git and checkbox is checked → defer git init to the first execution; the task record stores `pendingGitInit = true`.
4. Computes `nextRunAt` (see §4.3) — **never runs immediately**; first fire is at the first scheduled slot.
5. Persists via `ScheduledTaskStore.insertTask(...)`, closes the dialog.

### 3.2 Sidebar — "Scheduled" section

Lives in the **Sessions** sidebar tab as a collapsible section above the existing session groups.

**Section header**: chevron + "Scheduled (N)". Empty state is suppressed — the section only renders once at least one task exists. Creation is initiated from the sidebar toolbar's **+** menu.

**Sessions spawned by scheduled tasks live in the main sidebar list alongside regular sessions** — Active group while running, by-date Inactive groups after their window closes. The "Scheduled" section is a *task* index, not a session list; the only filtering happens when you tap a task row, which pushes into a detail view that shows only that task's session history.

Because some scheduled runs may close before Claude has written meaningful `.jsonl` content (and `SessionManager` filters out empty/header-only files), `SessionListView` augments `sessionManager.sessions` with a second `@Query(AllSessionsRequest())` that supplements the by-date groups with any DB-tracked session not already covered by the filesystem scan. Dedup is by `tenvySessionId` so the same session never shows twice.

**Row** (`ScheduledTaskRowView`): one per task, modelled on `SessionRowView`.

- Row icon: `clock` SF Symbol; colored by current status (see §4.5).
- Title: task name.
- Subtitle (`Text` below title): **relative-only countdown** to next run.
  - `"in 12s"`, `"in 3m 45s"`, `"in 2h 14m"`, `"in 3 days"` — never wall-clock.
  - Special states override the countdown text: `"Running"`, `"Skipped — previous still active"`, `"Last run failed"`, `"Disabled"`.
  - Countdown re-renders on a shared 1 Hz `TimelineView` (covers all rows; cheaper than per-row timers).
- Trailing controls: nothing on the row itself. Right-click context menu = `Enable` / `Disable` / `Delete`.

**Tap behavior**: pushes the sidebar to the task detail view (§3.4). Implementation: a `NavigationStack` *inside* the sessions tab (not the app's chrome). Reusing the sub-list pattern from existing scoped views.

### 3.3 Sidebar — "Scheduled" section navigation back

The push view (§3.4) replaces the sessions list inside the Sessions tab. A `←` back chevron in the top-left returns the sidebar to the flat list. Switching to the Changes tab and back returns to the sub-view (state is preserved while the sidebar tab is alive, matching the existing `ZStack` pattern in `SidebarView`).

### 3.4 Task detail view (push view)

`ScheduledTaskDetailView`:

```
[← Back]   <icon>  <Task name>                       [enable toggle] [×]
                                                                     (delete)
[ ▶ Details ]   ← disclosure, collapsed by default
   Frequency: Every 2 weeks on Mon, Wed at 09:00
   Folder:    /Users/x/Projects/foo
   Worktree:  /Users/x/Projects/foo/.worktrees/  (or custom path if set)
   Permissions:  default (3 allow rules)
   Prompt:    "Write a summary of yesterday's PRs..." [Show full ▾]
   Created:   2026-05-15  ·  Last run: 09:00 (running)

[Sessions list — uses SessionRowView, same chrome as regular sessions]
   ▣ Scheduled — Refresh PRs — 2026-05-15 09:00     ●  running
   ○ Scheduled — Refresh PRs — 2026-05-14 09:00        idle
   ...
```

- Enable toggle: see §4.6.
- Delete button (×): see §4.7.
- Disclosure expanded state is **not** persisted (local UI state).
- Prompt "Show full" opens a sheet with the full text or file path/contents preview.

### 3.5 Execution

When the in-app scheduler decides a task is due (§4.2):

1. Look up the previous spawned session for this task (DB: `sessions WHERE scheduledTaskId = X ORDER BY createdAt DESC LIMIT 1`).
2. Check overlap rule (§4.4). If skip → record skipped run, notify, recompute `nextRunAt`, stop.
3. Build a fresh `tenvySessionId`, generate the branch + worktree (§4.5), inject the prompt (§4.6).
4. Create a **new top-level window** (background, no focus steal — see §5.4), insert the `SessionRecord` with `scheduledTaskId` set, start the terminal.
5. Update the task: `lastRunAt = now`, `lastRunStatus = .running`, `nextRunAt = compute next slot`.
6. Post a macOS notification (every run + skips + failures notify).

### 3.6 Failure handling

If anything in steps 3–4 throws (worktree fails, file unreadable, branch collision after retries, etc.) the run is recorded as **failed**:

- `lastRunStatus = .failed`, `lastRunMessage = <reason>`.
- `enabled = false` — the task is auto-disabled.
- macOS notification with the reason.
- No partial session record is inserted; if a worktree was already created before the failure, it's torn down with `WorktreeService.removeWorktree`.

### 3.7 Skipped runs

When overlap rule says skip (§4.4):

- `lastRunStatus = .skipped`, `lastRunMessage = "Previous run still active"`.
- macOS notification.
- `nextRunAt` recomputed to the *next* slot (we don't re-fire the missed slot).
- No record in the sessions table.

### 3.8 Notifications

All scheduled-task notifications route through `NotificationService` with a dedicated category. Three kinds:

| Event | Title | Body |
|---|---|---|
| Run started | "Scheduled task started" | `<task name>` |
| Run skipped | "Scheduled task skipped" | `<task name> — previous run still active` |
| Run failed | "Scheduled task failed" | `<task name> — <reason>` |

Dedupe / focus-suppression rules already applied to session notifications still apply.

---

## 4. Runtime semantics

### 4.1 Scheduling model

For each task:

- `frequencyUnit ∈ {minute, hour, day, week}`
- `frequencyValue ∈ [1, 999]`
- `timeOfDay: (hour, minute)?` — required iff `frequencyUnit ∈ {day, week}`.
- `weekdays: Set<Weekday>?` — required iff `frequencyUnit == week`, non-empty.

**Validation lives in `ScheduledTask.validate()` and is enforced at insert and at scheduler-load time** (catches DB tampering / migration bugs).

### 4.2 Scheduler engine

`ScheduledTaskScheduler` is a singleton owned by `AppModel`. It owns one shared `Timer` that fires every **5 seconds** while the app is running.

- On each tick: query `scheduled_tasks WHERE enabled = true AND nextRunAt <= now` and for each candidate, hand it to `ScheduledTaskExecutor.execute(taskId:)`.
- Ticks happen on the main actor; execution work is dispatched asynchronously, so a slow execution can't delay the next tick.
- On app launch: start the timer, then immediately scan for tasks whose `nextRunAt < now` (i.e. missed-while-closed). For each such task, **recompute** `nextRunAt = nextSlotAfter(now)` and write it back. **Do not run** the missed slot (decision: skip missed). The recomputation is the only "catch-up" behavior.
- On app shutdown: stop the timer cleanly. No persistence of timer state is needed because `nextRunAt` is recomputed from scratch on every launch.

The 5-second tick is good enough — minute-frequency tasks may fire up to 5s late, which is acceptable. We explicitly chose this over a dispatch-source per task because (a) it's far simpler, (b) the number of tasks will be small, (c) it gives us a single audit point for "what's scheduled right now".

### 4.3 Computing `nextRunAt`

`ScheduledTask.computeNextRunAt(from anchor: Date) -> Date`

- **Minute / Hour**: `nextRunAt = anchor + frequencyValue × unit`. Anchor is `max(lastRunAt, createdAt)` for normal recurrence; on re-enable it's `Date()` (fresh anchor — decided in §4.6).
- **Day**: starting from `anchor`, find the next `Date` whose wall-clock time is `timeOfDay` and whose day index modulo `frequencyValue` matches the anchor's day. We avoid clever "every N days" anchor arithmetic by computing `nextRunAt = max(anchor, today@timeOfDay)`, then advancing in `+frequencyValue`-day steps until `> anchor`.
- **Week**: starting from `anchor`, find the next `Date` whose weekday is in `weekdays` and whose week index modulo `frequencyValue` matches. Same approach: walk forward day by day, snap to `timeOfDay`, advance by 7×N if no matching weekday in the current week.
- All calculations use `Calendar.current` in `TimeZone.current`. DST transitions are handled by `Calendar` — we do not roll our own time math.

### 4.4 Overlap rule (skip vs auto-close)

When a task is due and a previous session record exists for it:

| Previous session state | Action |
|---|---|
| `processing`, `thinking`, `waitingPermission` (or any non-waiting hook state) | **Skip** the new run. Record `.skipped`. |
| `waiting` (Stop hook fired — Claude is idle) | **Auto-close** the previous session, then start the new run. |
| Previous session not active (window closed, process gone) | Just start the new run. |
| `started` / no hook state yet (race window — just launched) | Treat as "non-waiting" → **skip** (safer; avoids killing a session that's still booting). |

Auto-close path: `SessionStore.deactivateSession(...)` + `ProcessManager.terminateProcess(...)` + close the window via the existing window-close path. The worktree is **NOT** removed (worktrees are retained until the task is deleted — see §4.7).

The previous session's record stays in DB and remains visible in the sub-list as historical.

### 4.5 Worktree / branch naming

For each execution:

- `slug = slugify(task.name)` — lowercase, `[^a-z0-9]+` → `-`, trim leading/trailing `-`, collapse repeats, truncate to 32 chars. If empty after slugifying, use `task-<8-char-task-id-prefix>`.
- `timestamp = "yyyyMMdd-HHmmss"` in UTC.
- Candidate branch: `tenvy/scheduled/<slug>/<timestamp>`.
- Worktree directory name: `<slug>-<timestamp>` (no slashes, to keep paths sane), placed under `task.customWorktreeBase ?? WorktreeService.defaultWorktreePath(...)`.

Collision handling (e.g., two manual triggers in the same second — unlikely, but defensive):

- Try the candidate. On `git worktree add` failure that indicates the branch exists, append `-1`, `-2`, … up to `-9` and retry. Beyond that, surface as a failure.

### 4.6 Enable / disable

- The task row has no inline switch; toggle lives in the detail view header.
- **Disable** flow:
  - If no session is currently running (no active row with `scheduledTaskId = X`), flip `enabled = false`, persist, done.
  - If a session is running, present a sheet `DisableRunningTaskConfirmationView`:
    - Buttons: **Stop & disable** / **Disable, let current run finish** / Cancel.
    - "Stop" path → terminate the running session (same plumbing as the auto-close path in §4.4), then flip enabled.
    - "Let finish" path → flip enabled only; the running session stays alive until it finishes / closes normally.
- **Enable** flow:
  - `lastRunAt = nil` is not changed; `nextRunAt = computeNextRunAt(from: Date())` — **fresh anchor from re-enable time** (decided in clarification round 7).
  - Persist.

### 4.7 Delete

Trigger: `×` button in detail view header. Opens `DeleteScheduledTaskConfirmationView`.

The dialog is **stateful** — it represents an in-progress destructive operation, not a yes/no question.

1. Initial state: lists what will be removed (counts and a few example paths):
   - The scheduled task definition.
   - N spawned sessions (with a checkbox **"Also delete the spawned sessions"** — default on).
   - M worktree directories (with a checkbox **"Also delete worktrees"** — default on; only shown if any are still on disk).
2. Confirm button → dialog enters **"Cleaning up…"** state. Shows a progress indicator (`ProgressView`) and per-step status text. The dialog cannot be dismissed during this phase.
3. Cleanup steps, sequential, each updates the dialog:
   1. If "delete sessions" — for each spawned session: if running, terminate it; then call `SessionStore.deleteSession`.
   2. If "delete worktrees" — for each worktree path: `WorktreeService.removeWorktree(repoPath:, worktreePath:)`. Failures are collected and surfaced at end (do not abort the loop).
   3. Delete the `ScheduledTaskRecord`.
4. On success: brief checkmark animation, dialog closes after ~600ms, sidebar navigates back to the flat sessions list.
5. On partial failure: dialog enters **"Some items couldn't be removed"** state, lists the failures, has a **Close** button. The task record itself is still deleted on the final step only if all earlier steps succeeded; if cleanup is partial, the task is left in place with the cleanup work tracked (see §6 for failure-mode details).

If "delete sessions" / "delete worktrees" boxes are unchecked at confirm time, those steps are skipped. Unchecking "delete sessions" but checking "delete worktrees" is allowed (the sessions become history rows pointing to a missing folder — same as if the user manually removed a worktree directory).

---

## 5. Execution: window, terminal, prompt injection

### 5.1 Session record fields

A scheduled-spawned session is a normal `SessionRecord` plus one new column `scheduledTaskId: String?` (see §6 — migration v4).

- `tenvySessionId`: fresh UUID.
- `title`: `"<Task name> — yyyy-MM-dd HH:mm"` in local time.
- `workingDirectory`: the worktree path.
- `projectPath`: the worktree path (same — that's our convention for new-session-with-worktree).
- `branchName`: the timestamped scheduled branch.
- `worktreePath`: the worktree path.
- `isPlainTerminal`: `false`.
- `isActive`: `true`.
- `permissionSettings`: snapshot from the task (the task carries its own JSON-encoded `ClaudePermissionSettings`; copied verbatim onto the session record at execution time so the inspector behaves identically to a normal session).
- `scheduledTaskId`: the task's id.

### 5.2 Permission inheritance

The task stores its own `permissionSettings` (defaults from `ClaudeSettingsService.mergeForNewSession()` at task creation, then user-editable in the create/edit form). At execution time the task's `permissionSettings` is copied to the session record. Live edits to the task's permissions only affect *future* runs; the already-running session keeps the permissions it was launched with — there is no "restart with new permissions" button on scheduled tasks.

### 5.3 Prompt injection

Decision: **launch Claude with the prompt as the trailing positional argument** — `claude [options] "<prompt>"`. The Claude CLI treats it as the first user message and starts processing immediately. No hook-based injection, no `sendText` timing dance, no TUI-readiness race.

- The executor resolves the prompt up-front (text from the task record, or the file contents at `task.promptFilePath`, re-read each run, 1 MB cap). File missing / unreadable / oversized → fail the run before opening any window.
- It calls `ContentViewModel.setInitialPrompt(tenvySessionId:prompt:)` on the new window's view model before the terminal mounts.
- `ClaudeSessionTerminalView` exposes an `initialPromptProvider: (() -> String?)?` (a closure, **not** an eagerly-read string). `ContentView` passes `{ viewModel?.initialPrompt(for: session.tenvySessionId) }`. `makeNSView` invokes the closure exactly once at mount time and appends the result as the final positional argument to `claude`. Using a closure is critical — `viewModel.initialPrompt(for:)` is consume-on-read, and SwiftUI re-evaluates `PaneLeafView.terminalView` multiple times while the window is going through `windowConfigured` / `selectedSession` configuration. An eagerly-read string would be consumed by an early body eval and the struct that ultimately reached `makeNSView` would carry `nil`.
- The prompt is only appended when the launch is **fresh** (no `--resume`, no `--fork-session`). That means a session reopened later from the by-date list won't re-submit the prompt.
- `TerminalEnvironment.shellArgs` already single-quote-escapes each argument, so multi-line prompts and embedded special characters pass through correctly.
- No timeout to worry about — if Claude can't launch, the existing process-spawn failure surfaces; if the prompt is broken, the run is already marked failed before the window opens.

The terminal launch flow is otherwise unchanged. `ClaudeSessionTerminalView` does not need scheduled-task awareness; we add a one-time injection observer at the `ContentViewModel` level keyed on `tenvySessionId`.

### 5.4 Window placement

Each execution opens a brand-new top-level NSWindow, **background (not key)**:

- Reuse the existing AppKit window-creation path used by `handleDragToNewWindow` (creates an `NSWindow` + `NSHostingController<ContentView>`).
- Do **not** call `window.makeKeyAndOrderFront(_:)`. Use `window.orderBack(nil)` or `orderFront(nil)` without making it key. The window appears at the back of the window list and does not steal focus.
- The new window's `ContentViewModel` is constructed with the spawned session preselected. We do **not** preload a GhosttyHostView here (unlike drag-to-new-window) — the terminal goes through the normal `makeNSView` path inside the new window.
- Window title binds to the session title (existing wiring).
- If the user later activates the new window, it focuses normally.

### 5.5 Multi-window invariant

`WindowSessionRegistry` already ensures one window per session. We add nothing here; the registry sees the scheduled-spawned session like any other.

The **task-level** "one window at a time" invariant is enforced by the §4.4 overlap rule, not by the registry. A task never has two active spawned sessions because before a new one starts, the previous is either gone (closed) or killed (auto-close) or the new run was skipped.

---

## 6. Data model

### 6.1 New table: `scheduledTask`

GRDB migration **v4_createScheduledTask** in `AppDatabase`:

```sql
CREATE TABLE scheduledTask (
  id                      TEXT    PRIMARY KEY NOT NULL,
  name                    TEXT    NOT NULL,
  workingDirectory        TEXT    NOT NULL,
  customWorktreeBase      TEXT,                       -- nil → defaultWorktreePath
  pendingGitInit          INTEGER NOT NULL DEFAULT 0, -- BOOL
  frequencyUnit           TEXT    NOT NULL,           -- "minute"|"hour"|"day"|"week"
  frequencyValue          INTEGER NOT NULL,
  timeOfDayHour           INTEGER,                    -- 0..23, for day/week
  timeOfDayMinute         INTEGER,                    -- 0..59, for day/week
  weekdays                TEXT,                       -- comma-joined "1,2,5" for week
  promptKind              TEXT    NOT NULL,           -- "text"|"file"
  promptText              TEXT,                       -- when kind == "text"
  promptFilePath          TEXT,                       -- when kind == "file"
  permissionSettings      TEXT    NOT NULL,           -- JSON, same shape as SessionRecord
  enabled                 INTEGER NOT NULL DEFAULT 1, -- BOOL
  createdAt               DOUBLE  NOT NULL,
  lastRunAt               DOUBLE,
  lastRunStatus           TEXT,                       -- "running"|"skipped"|"failed"|"completed"
  lastRunMessage          TEXT,
  lastRunSessionId        TEXT,                       -- FK to sessionRecord.tenvySessionId (best-effort, no SQL constraint)
  nextRunAt               DOUBLE  NOT NULL
);

CREATE INDEX scheduledTask_nextRunAt_idx ON scheduledTask(enabled, nextRunAt);
```

`weekdays` uses comma-joined integers (`1`=Sun … `7`=Sat per `Calendar.weekday`) for cheap encoding without a join table.

`lastRunStatus` values:

- `running`: there is currently a session in flight whose `tenvySessionId == lastRunSessionId`. The sidebar/detail show its live state via the existing `SessionRuntimeRegistry`.
- `completed`: the last spawned session reached `waiting` or was closed; treated identically to `running` from the user's POV (countdown until next run).
- `skipped`: last attempt was skipped by the overlap rule.
- `failed`: last attempt errored; the task is now disabled.

### 6.2 Migration v5 — extend `sessionRecord`

Add nullable foreign-key column:

```sql
ALTER TABLE sessionRecord ADD COLUMN scheduledTaskId TEXT;
CREATE INDEX sessionRecord_scheduledTaskId_idx ON sessionRecord(scheduledTaskId);
```

No SQL `FOREIGN KEY` constraint — we deliberately allow orphan rows (session can outlive its task if the user deletes the task while opting to keep sessions).

### 6.3 GRDB records and queries

- `ScheduledTaskRecord: Codable, FetchableRecord, PersistableRecord, Identifiable` — mirrors `SessionRecord`'s style. Includes computed `nextRunDate`, `lastRunDate`, decoded permissions, decoded weekdays, decoded `Frequency` value object.
- `AllScheduledTasksRequest: ValueObservationQueryable` — fetch ordered by name.
- `ScheduledTaskByIdRequest`.
- `SessionsByScheduledTaskRequest(taskId: String)` — used by the detail sub-list.

### 6.4 Write discipline

A new singleton `ScheduledTaskStore` (parallel to `SessionStore`) is the **sole writer** to the `scheduledTask` table:

- `insertTask(_ record: ScheduledTaskRecord) throws`
- `deleteTask(id: String) throws`
- `setEnabled(id:, enabled:) throws`
- `markRunStarted(id:, sessionId:, runAt:, nextRunAt:) throws`
- `markRunSkipped(id:, at:, nextRunAt:, reason:) throws`
- `markRunFailed(id:, at:, reason:) throws` (also flips enabled to false)
- `setNextRunAt(id:, at:) throws` (used by missed-run-on-launch recompute and on re-enable)

Views never write directly; `ContentViewModel` (or the new scheduled-tasks ViewModel — see §7) routes actions to the store.

---

## 7. File layout (new + modified)

### 7.1 New files

```
Tenvy/
├── Core/
│   ├── ScheduledTaskRecord.swift       # GRDB record + query types
│   └── ScheduledTaskStore.swift        # Sole writer for scheduled_tasks
└── Features/
    └── Scheduled/
        ├── ScheduledTask.swift                       # Value types: ScheduledTask (domain),
        │                                             # Frequency, Weekday, PromptKind, RunStatus
        ├── ScheduledTaskScheduler.swift              # 5s timer, drives executor
        ├── ScheduledTaskExecutor.swift               # Builds branch/worktree, opens window, injects prompt
        ├── ScheduledTaskPromptInjector.swift         # SessionStart-hook listener + sendText
        ├── ScheduledTaskSidebarSection.swift         # Collapsible section header + rows
        ├── ScheduledTaskRowView.swift                # One row, status icon + countdown
        ├── ScheduledTaskDetailView.swift             # Push view: header + sub-list
        ├── ScheduledTaskDetailHeaderView.swift       # Compact + expandable disclosure
        ├── CreateScheduledTaskView.swift             # Creation dialog (form)
        ├── DisableRunningTaskConfirmationView.swift  # Sheet on disable
        ├── DeleteScheduledTaskConfirmationView.swift # Stateful delete dialog (progress)
        └── ScheduledTaskCountdownFormatter.swift     # "in 3m 45s" etc.
```

### 7.2 Modified files

- `Tenvy/Core/AppDatabase.swift` — add v4 + v5 migrations.
- `Tenvy/Core/SessionRecord.swift` — add `scheduledTaskId` column, add `SessionsByScheduledTaskRequest`.
- `Tenvy/Core/AppModel.swift` — own the `ScheduledTaskScheduler` instance; start it after DB is ready; wire `HookEventService` → `ScheduledTaskPromptInjector` for SessionStart events.
- `Tenvy/Shared/SidebarView.swift` — pass scheduled tasks through; host the `NavigationStack` for the section push view (or equivalent).
- `Tenvy/Features/Session/SessionListView.swift` — host the new `ScheduledTaskSidebarSection` at the top of the list; collapsible state in `@AppStorage`.
- `Tenvy/Features/Session/SessionGroupingService.swift` — no change required; scheduled-spawned sessions still group by project like any other.
- `Tenvy/App/AppState.swift` — expose the scheduler / store via the existing dependency container.
- `Tenvy/App/NotificationService.swift` — add a `scheduledTask` category and the three notification payloads from §3.8.
- `Tenvy/Features/Git/WorktreeService.swift` — no API changes; we reuse `createWorktree`, `removeWorktree`, `initGitRepo`, `findRepoRoot`, `defaultWorktreePath`.
- `Tenvy/Features/Git/NewSessionDialogView.swift` — no change (we ship a dedicated creation dialog; not reusing this one).
- `Tenvy/App/ContentView.swift` / `ContentViewModel.swift` — wire the "open scheduled session in a background window" entry point (similar to `handleDragToNewWindow`).

### 7.3 No changes needed

- `ClaudeSessionTerminalView` (scheduled-spawned sessions launch through the existing path).
- `Inspector` (no affiliation surfaced per decision).
- `PaneSplitTree`, splits — scheduled sessions never split.
- `IDE` integration — works automatically for scheduled-spawned sessions because they're regular sessions.

---

## 8. Concurrency, threading, and invariants

- All scheduler ticks and DB writes happen on the **main actor**. GRDB writes inside `ScheduledTaskStore` are synchronous and brief.
- `ScheduledTaskExecutor.execute(taskId:)` is `@MainActor async`. It awaits worktree creation (which shells out via `Process` — already main-safe in `WorktreeService`).
- Hook-event injection is best-effort: if the user closes the window before the SessionStart hook arrives, the injection listener is canceled.
- We never spawn a Task to "re-fire later if conditions clear." The scheduler tick is the only retry mechanism. Skipped runs are not re-queued; the next regular slot is the next chance.
- App quit while a scheduled session is running: the existing process-cleanup signal handlers tear it down (same as a manual session). On next launch, the session record's `isActive` is reset by the normal startup path; the task's `lastRunStatus` may still read `running` — startup reconciliation marks it `completed` if there is no longer an active session matching `lastRunSessionId`.

---

## 9. Edge cases and what we do about them

| # | Case | Behavior |
|---|---|---|
| 1 | Folder is deleted between creation and first run | Worktree creation fails → run fails → auto-disable. |
| 2 | Folder is a worktree itself, not a regular repo | We treat it as a normal git folder. `WorktreeService.findRepoRoot` already resolves to the main repo for `git worktree add`. |
| 3 | User-supplied custom worktree base path doesn't exist | We create intermediate dirs (`FileManager.createDirectory withIntermediates: true`). If that fails, run fails. |
| 4 | Branch with the slugged name already exists (manual creation by user, prior run, etc.) | Append `-1`…`-9`; if all collide, run fails. |
| 5 | Task name contains only non-ASCII or only emoji | Slug fallback to `task-<8 char id prefix>`. |
| 6 | User changes system clock | Scheduler may fire immediately for tasks now in the past, or wait a long time for tasks in the future. We do not try to detect this — `Calendar.current` handles DST; clock changes are a known limitation. |
| 7 | DST forward jump skips the anchor (e.g., 02:30 daily on the spring-forward day) | `Calendar.nextDate(after:matching:...)` returns the next valid wall-clock time. We rely on it; do not roll our own. |
| 8 | Prompt file is 1 MB+ | Run fails with "Prompt file too large". |
| 9 | Prompt file is a symlink | We resolve and read the target. Same size limit. |
| 10 | Permissions JSON in the task is corrupt at execution time | Treat as inherit-defaults; log a warning. Do not fail the run for this. |
| 11 | The SessionStart hook never fires (Claude crashed at launch) | 60s injection timeout → run fails → auto-disable. The launched window stays — user can investigate. |
| 12 | User closes the spawned window while injection is pending | Cancel injection. Mark `lastRunStatus = completed` (window-close = end-of-run). |
| 13 | Two tasks fire on the same tick | They execute serially (main actor + async/await). Each gets its own window. |
| 14 | The Scheduled section's collapsed/expanded state | Persisted in `@AppStorage` so it survives app launches. |
| 15 | User deletes a task while a confirmation dialog for another task is open | The dialog operates on a captured task id; the row simply disappears under it. We accept this minor visual glitch. |
| 16 | Sub-list session was created by a now-deleted task (orphan path) | Sessions list still shows them normally; they just can't be filtered via the deleted task anymore. |
| 17 | User toggles enable rapidly | `ScheduledTaskStore.setEnabled` is serialized via GRDB write transactions. Last toggle wins. |
| 18 | App crashes mid-execution | On next launch, reconciliation (§8) flips any `lastRunStatus = running` whose `lastRunSessionId` no longer corresponds to an active session to `completed`. `enabled` is preserved. |
| 19 | Notification permissions denied | Notifications silently no-op (existing `NotificationService` behavior). Sidebar status is still authoritative. |
| 20 | The task's working folder is on an external/unmounted volume at execution time | Worktree creation fails → run fails → auto-disable. |

---

## 10. Tests

Minimum bar for ship:

- `ScheduledTask.computeNextRunAt` exhaustive tests:
  - Every unit at the day/DST boundary.
  - Week with one weekday vs many weekdays.
  - `from` anchor in the past, present, future.
  - DST forward and back.
- `ScheduledTask.validate` rejects each invalid permutation.
- `ScheduledTaskExecutor` integration test against an in-memory GRDB and a mocked `WorktreeService`:
  - Happy path inserts a `SessionRecord` with the right fields and updates the task.
  - Skip path inserts no session, updates `lastRunStatus = skipped`, recomputes `nextRunAt`.
  - Failure path tears down the partial worktree, marks failed, disables the task.
  - Overlap auto-close path terminates the prior session.
- `ScheduledTaskCountdownFormatter` snapshot strings for each scale.
- Slug + collision tests (`tenvy/scheduled/<slug>/<ts>` → append `-1`).

UI tests are not required for v1 (existing project follows the same pattern).

---

## 11. Documentation updates required (per `.claude/rules/pr-documentation.md`)

When the implementation lands, the following must be updated in the same PR:

- `CLAUDE.md`:
  - Quick Overview: add a "Scheduled Tasks" bullet.
  - Architecture diagram: add the new `Features/Scheduled/` directory.
  - Critical Implementation Details: add a "Scheduled Tasks" section summarizing the runtime invariants (overlap rule, missed-run policy, prompt injection mechanism, no run-now).
- `FEATURES.md`: full feature write-up mirroring §3 of this doc.
- `.claude/memory/`:
  - New file: `project_scheduled_tasks.md` — overlap rule, missed-run policy, frequency model, prompt injection, worktree retention.
  - Index it in `MEMORY.md`.
- `.claude/rules/`:
  - No new permanent rules; the doc above is the spec.

---

## 12. Implementation order (suggested milestones)

Each milestone should be independently testable and reviewable.

1. **Data layer.** GRDB migrations v4 + v5, `ScheduledTaskRecord`, `ScheduledTaskStore`, value types (`Frequency`, `Weekday`, `PromptKind`, `RunStatus`), validation, `computeNextRunAt` with unit tests. No UI.
2. **Scheduler skeleton.** `ScheduledTaskScheduler` timer + missed-run reconciliation on launch. No executor yet — just log "would fire task X". Wire into `AppModel`.
3. **Executor — happy path.** Worktree creation, `SessionRecord` insertion, background window opening. No prompt injection yet — just verify a fresh Claude launches in the right place.
4. **Prompt injection.** SessionStart-hook listener, text + file prompts, 60s timeout. Integration test.
5. **Overlap rule + failure handling.** Skip vs auto-close decisions, auto-disable on failure, notification dispatch.
6. **Sidebar.** "Scheduled" section, `ScheduledTaskRowView` with countdown, push navigation to `ScheduledTaskDetailView`.
7. **Creation dialog.** `CreateScheduledTaskView`, validation, git-init checkbox path, permissions editor embed.
8. **Detail view.** Compact + expandable header, enable toggle (with running-confirmation sheet), session sub-list.
9. **Delete dialog.** Stateful progress UI, worktree cleanup, partial-failure surfacing.
10. **Documentation.** §11 above. (Concurrent with implementation — not as an afterthought.)

Each milestone gets its own commit and PR (or stacked PRs). Do not bundle.

---

## 13. Open risks called out for review during implementation

These are deliberate uncertainties that the spec does not pre-decide; if they surface as actual problems during implementation, surface them rather than papering over:

- **5-second tick precision** for minute-frequency tasks: jitter up to 5s. If users complain, revisit per-task `DispatchSourceTimer`.
- **Background window UX**: macOS may still flash the dock icon when a new window appears. If it does, evaluate suppressing the dock bounce.
- **SessionStart hook reliability** as the prompt injection trigger: if it proves flaky (e.g., Claude versions that emit it inconsistently), we'd need a fallback like a timed delay + presence check.
- **Worktree retention "forever"** means disk usage grows. We accept this for v1 (decision logged); if it bites real users, add a per-task retention setting.
- **Calendar weekday encoding**: `Calendar.current.firstWeekday` differs by locale. We store ISO weekday numbers (`1`=Sun, `7`=Sat per `Calendar.weekday`) and render with locale-appropriate names — verify on a non-en locale before shipping.

---

## 14. Decisions log

Every product-shaping decision agreed during planning. Use this as a reference when reviewing PRs:

| # | Decision | Chosen | Rejected |
|---|---|---|---|
| 1 | Previous waiting session vs new run | Auto-close previous | Skip; per-task toggle |
| 2 | Missed runs while app closed | Skip | Catch-up; prompt user |
| 3 | Frequency model | Interval + time-of-day | Interval-only; cron |
| 4 | Prompt injection mechanism | Interactive + `sendText` after SessionStart | `--print` flag; stdin pipe |
| 5 | Git strategy options | Worktree only (with git init for non-git folders) | + current branch; + new branch |
| 6 | Sidebar surfacing | Section in Sessions tab | New tab; mode switch |
| 7 | Permission default | Inherit global, editable per task | Bypass default; force pick |
| 8 | Non-git folder | Offer git init + worktree | Allow in-place; block |
| 9 | First run timing | First scheduled slot | Immediate; checkbox |
| 10 | Management actions | Enable/disable + Edit + Delete | + Run Now; + Duplicate |
| 11 | Delete cascade | Confirmation dialog with worktree cleanup + progress animation | Always keep history; always cascade |
| 12 | File prompt re-read | Re-read each execution | Snapshot at creation; per-task toggle |
| 13 | Window mode | New separate window, background | New separate window, foreground; tab |
| 14 | Notifications | Every run + skips + failures | Skips + failures only; none |
| 15 | Failure behavior | Auto-disable + notify | Sidebar-only; retry-with-backoff |
| 16 | Worktree retention | Keep forever until task delete | Remove on session close; retention setting |
| 17 | Week scheduling controls | Every N weeks + weekdays + time | Weekdays + time (N=1); interval + time |
| 18 | Sub-list navigation | Push (replace sidebar content) | Inline expand; right-side panel |
| 19 | Disable behavior with running session | Confirm if running | Always finish; always kill |
| 20 | Sidebar status visualization | Status icon + countdown | Dot + subtitle; pill badges |
| 21 | Affiliation on session row / inspector | Not surfaced | Both; inspector only |
| 22 | Scheduler tick | Fixed 5s | Adaptive; per-task dispatch source |
| 23 | Sub-list contents | Only actual sessions | Mixed timeline; separate runs log |
| 24 | Create entry point | Menu on main toolbar `+` (default click → New Session; menu item → New Scheduled Task) | `+` on section header; both |
| 25 | Branch naming | `tenvy/scheduled/<slug>/<ts>` | `<slug>-<ts>`; `<slug>/<ts>` |
| 26 | Countdown format | Relative only | Adaptive (relative + wall-clock); absolute |
| 27 | Detail header | Compact + expandable disclosure | Full summary; tabbed |
| 28 | Re-enable scheduling | Fresh from re-enable time | Preserve original anchor; ask user |
| 29 | Prompt input UI | Segmented control (Text/File) | Both fields; radio |
