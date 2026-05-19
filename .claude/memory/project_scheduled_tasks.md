# Scheduled Tasks

> Authoritative design lives at `scheduled-tasks.md` (repo root). This memory file is a
> quick orientation for future conversations and a cross-link to the long-form spec.

## What it is

Recurring Claude Code "tasks" the user defines once. Each firing opens a fresh background
window with a Claude session pre-seeded with a user-provided prompt. By default the run
executes directly in the chosen folder (no git involvement); when the task opts in to
`useWorktree`, each firing creates a fresh git worktree off the folder's current branch
instead.

## Surface area

- New tables (GRDB migrations v4 + v5 + v6):
  - `scheduledTask` — task definitions.
  - `sessionRecord.scheduledTaskId` — optional FK from sessions to their parent task.
  - `scheduledTask.useWorktree` — per-task flag (migration v6). The same migration
    wipes pre-v6 rows because they were created under the worktree-always assumption.
- New files under `Tenvy/Features/Scheduled/`:
  - `ScheduledTask.swift` — value types (`Frequency`, `Weekday`, `PromptKind`, `RunStatus`),
    `nextRunAt` algorithm, branch/slug naming helpers.
  - `ScheduledTaskScheduler.swift` — fixed 5-second tick loop, missed-run reconciliation.
  - `ScheduledTaskExecutor.swift` — worktree creation, session insert, background window,
    overlap rule (§4.4), failure handling. Also resolves the prompt (text/file) and hands
    it to the new window's `ContentViewModel` via `setInitialPrompt(tenvySessionId:prompt:)`.
  - `ScheduledTaskRowView.swift` — sidebar row (status icon + countdown). The
    section is rendered inline in `SessionListView` (no wrapper struct — wrapping
    `Section(isExpanded:)` in a `View` struct broke `List`'s sidebar parsing).
  - `ScheduledTaskPowerGuard.swift` — holds `IOPMAssertion`s (system + display)
    while any scheduled session is alive; prevents idle sleep / screen saver
    mid-run. Debounced unregister survives the temp-UUID → claudeId sync swap.
  - `ScheduledTaskDetailView.swift` — push view: compact header + expandable disclosure
    + session sub-list. Enable/disable toggle. Delete button opens the delete dialog.
  - `CreateScheduledTaskView.swift` + `ScheduledTaskFormModel` — creation form.
  - `DeleteScheduledTaskConfirmationView.swift` + `DeleteScheduledFlowModel` — stateful
    delete dialog with cleanup progress.
  - `ScheduledTaskCountdownFormatter.swift` — "in 3m 45s" etc.
- New files under `Tenvy/Core/`:
  - `ScheduledTaskRecord.swift` — GRDB record + `@Query` request types.
  - `ScheduledTaskStore.swift` — sole writer for the `scheduledTask` table.
- `AppModel` now owns `scheduledTaskStore`, `scheduledTaskScheduler`,
  `scheduledTaskExecutor`, and `scheduledTaskPowerGuard`. `wireScheduledTasks()`
  builds them and assigns `scheduler.onTaskDue` to the executor's `execute(_:)`.
  There is **no** prompt-injector class anymore — the prompt is a positional CLI
  arg, so the executor hands it directly to the spawned window's
  `ContentViewModel`. The power guard is registered by the executor (after
  `openBackgroundWindow`) and unregistered (1-second debounce) by
  `AppModel.deactivateSession` so the assertion stays stable across the
  deactivate-then-activate hop inside `syncSessionFromHookEvent`.

## Core runtime invariants

- **One window per task at a time.** Enforced by the overlap rule, not by any registry.
- **Overlap rule** (§4.4): previous session in `waiting` → auto-close and proceed;
  previous in any other non-ended state → skip the new run; previous gone → proceed.
  The `started` / nil / unknown states count as "still occupying" — defensive.
- **Missed runs while app closed** are skipped on launch. The scheduler only rolls
  `nextRunAt` forward; it does not fire backlog.
- **No catch-up loops, no retries.** The next scheduled slot is the only retry.
- **First run waits for the first natural slot.** Saving a task never fires immediately.
- **Re-enable uses a fresh anchor** (`Date()` at re-enable time), not the original
  schedule anchor.
- **Auto-disable on failure.** Worktree creation, file-prompt I/O, SessionStart timeout,
  and any other run error flips `enabled = false` and posts a failure notification.

## Window opening

Spawned sessions open as a **new NSWindow built directly via `NSHostingController`**
(mirrors `ContentViewModel.handleDragToNewWindow`), but **without** `makeKeyAndOrderFront`
— `orderFront(nil)` so the window is visible but does not steal focus from the user's
active app. The window's `ContentViewModel` is preloaded with the session via
`preloadForTransfer(session:hostView:nil:isPlainTerminal:false)`; the regular
`shouldRenderTerminal` gate then triggers `makeNSView` once the window mounts.

### Window delegate gotcha (don't regress)

`WindowDelegate` (which runs the close confirmation and deactivates the session in
`windowShouldClose`) is attached by `AppDelegate` in **two** places:
1. `applicationDidFinishLaunching` iterates `NSApp.windows` once on launch.
2. `handleWindowBecameKey` observes `NSWindow.didBecomeKeyNotification` and lazily
   assigns the delegate the first time a window becomes key.

Background-spawned scheduled windows hit **neither** path: they are created after
launch, and `orderFront(nil)` does not make them key. Without the delegate the
default close behavior runs — the X button just orders the window out
(`isReleasedWhenClosed = false` means it isn't released), so `windowShouldClose`
never fires. The session stays in `activatedSessions`, claude keeps running, and
the `WindowSessionRegistry` entry persists. Clicking the session in the sidebar
finds the hidden window via `WindowSessionRegistry.window(for:)` and
`makeKeyAndOrderFront`s it back — *that* call finally triggers the lazy delegate
assignment, so the next close finally shows the termination prompt.

Fix: `ScheduledTaskExecutor.openBackgroundWindow` explicitly attaches
`AppDelegate.windowDelegate` to the new window right after construction. The
property was bumped from `private lazy` to `internal lazy` to allow this. If you
ever add another path that creates an `NSWindow` without `makeKeyAndOrderFront`,
apply the same explicit `window.delegate = …` assignment or sessions will leak
the same way.

## Prompt injection mechanism

The prompt is passed to Claude as the **trailing positional argument** of the launch
command (`claude [options] "<prompt>"`). The Claude CLI's `[prompt]` arg starts an
interactive session with that text submitted as the first user message — no need to
hook into `SessionStart`/`Stop` events or simulate `sendText`+Enter timing.

Flow:
1. Executor resolves the prompt up front (text or file, 1 MB cap on files). File errors
   surface as a `failed` run *before* any worktree or window is created.
2. Executor stashes the prompt on the new window's `ContentViewModel` via
   `setInitialPrompt(tenvySessionId:prompt:)`.
3. `ClaudeSessionTerminalView.makeNSView` consumes the prompt via
   `viewModel.initialPrompt(for:)` and appends it to the args list — *only* when the
   launch is fresh (no `--resume`, no `--fork-session`), so reopening a session from
   the by-date list later does not re-submit the prompt.
4. `TerminalEnvironment.shellArgs` already single-quote-escapes each argument, so
   multi-line text passes through cleanly.

No hook-based injection, no timing windows, no failure-prone Enter simulation.

### Variadic-flag gotcha (don't regress)

Claude's `--allowedTools <tools...>` and `--disallowedTools <tools...>` are declared
variadic in the CLI's commander schema. With the space-separated argv form
(`--allowedTools 'Edit Write Bash(*)' 'How do you do?'`) the parser greedily eats
the prompt as another tool name, and Claude opens with no first message.

`ClaudeSessionTerminalView.makeNSView` therefore emits permission flags as
`--flag=value` (single argv entry per flag — including `--permission-mode=...`
for symmetry). This binds the value to the flag and leaves the trailing prompt
arg untouched. If a future change reverts these to separate `--flag` / `value`
args, scheduled tasks will silently lose their prompts again.

## Worktree mode (per task, default OFF)

Each task carries a `useWorktree: Bool` flag. The create form's "Create a fresh git
worktree for every run" checkbox writes this flag; the default is **OFF**.

- **OFF (in-place)**: `ScheduledTaskExecutor.prepareWorkspace` skips git entirely and
  returns `Prepared(repoRoot: task.workingDirectory, branchName: nil, worktreePath: nil)`.
  The session record's `branchName` and `worktreePath` are nil, so the delete dialog's
  worktree-cleanup step naturally skips them. The folder is **not required** to be a git
  repository in this mode — no `git init` prompt is offered.
- **ON (worktree-per-run)**:
  - Branch: `tenvy/scheduled/<slug>/<YYYYMMDD-HHMMSS>` (UTC timestamp).
  - Worktree dir name: `<slug>-<YYYYMMDD-HHMMSS>` (flat, no slashes).
  - On branch collision: append `-1`…`-9`. Beyond that → fail the run.
  - `customWorktreeBase` overrides the default `<repo>/.claude/worktrees` parent.
  - Non-git folders require the "Initialize git on first run" opt-in (gated by
    `pendingGitInit` on the record).
  - **Worktrees are retained until the task itself is deleted** (per design decision).
    Disk-growth implications were explicitly accepted in §13 risks.

## Sidebar surface

A collapsible "Scheduled" section sits **above** the existing Active / by-date groups in
`SessionListView`. The section is hidden entirely when no tasks exist. State persisted in
`@AppStorage("sidebar.scheduledSectionExpanded")`. **Creation is initiated from the
sidebar toolbar's `+` button** (a split menu: default action → New Session; menu item →
New Scheduled Task). Tapping a row sets `navigatedScheduledTaskId`, which makes
`SessionListView` swap its `primaryContent` to `ScheduledTaskDetailView` (back chevron
returns to the flat list).

Status icon + relative countdown only. Format: `"in 12s"`, `"in 3m 45s"`, `"in 3 days"`,
`"due now"`. `TimelineView(.periodic(...))` re-renders at an interval scaled to the
remaining time (1s → 15s → 60s → 600s).

### Detail-view sub-list — resolving runtime state

The sessions sub-list inside `ScheduledTaskDetailView` must show the same live PID/CPU/
hook state as the main list. Two gotchas to preserve:

1. **Tap action goes through `onSessionSelect` → `onAction(.select(...))`** on the parent
   `SessionListView`, *not* by setting the `selectedSession` binding directly. Setting
   the binding bypasses `ContentViewModel.selectSession` (window registry, activation,
   runtime wiring), so the click would appear to do nothing.
2. **Row data must come from the live activated session, not the DB record.** The DB
   record's `isActive` flag is a snapshot that lags hook events, and its `claudeSessionId`
   may not yet match the runtime registry key (the registry is keyed by the *current*
   `session.id` — temp UUID before hook sync, Claude id after). The detail view looks up
   the live session by stable `tenvySessionId` in `appModel.activatedSessions`; when
   found, it passes that session's `id` to the runtime registry and `isActive: true` to
   `SessionRowView`. Falls back to the DB record only for history rows.

## Decisions explicitly out of scope

- No edit (delete + recreate).
- No "Run Now" button.
- No affiliation surfaced on regular session rows or in the inspector for
  scheduled-spawned sessions.
- No skipped/failed entries in the sub-list — only real sessions.
- No global "Scheduled" sidebar tab — section in the Sessions tab only.

## Where to look first

- For semantics: `scheduled-tasks.md`.
- For runtime entry point: `AppModel.wireScheduledTasks()` and
  `ScheduledTaskScheduler.tick`.
- For overlap rule: `ScheduledTaskExecutor.decideOverlap`.
- For UI: the inline `Section` in `SessionListView` (anchored on
  `@AppStorage("sidebar.scheduledSectionExpanded")`), `ScheduledTaskRowView`,
  `ScheduledTaskDetailView`, `CreateScheduledTaskView`.
- For the `--allowedTools` prompt-swallow gotcha: "Variadic-flag gotcha" section
  above and the comment block in `ClaudeSessionTerminalView.makeNSView`.
