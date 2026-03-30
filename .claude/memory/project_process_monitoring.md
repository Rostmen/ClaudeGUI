---
name: Process monitoring and termination (Ghostty/sysctl)
description: How Tenvy discovers and kills claude processes; why sysctl replaced ps; Ghostty SIGCHLD deadlock
type: project
---

Ghostty installs a SIGCHLD handler that reaps all child processes — including any `ps` subprocess spawned via `Process()` — before `waitUntilExit()` can observe the exit. This causes a permanent deadlock.

**Fix applied**: replaced all `Process()`/`ps` usage with `sysctl` kernel calls:
- `ProcessPoller` (hot path, 500 ms): `sysctl(KERN_PROC_ALL)` + `KERN_PROCARGS2` + `proc_pidinfo(PROC_PIDTASKINFO)` for PID/PPID/args/RSS/CPU
- `ProcessManager.findChildProcesses` (termination path): same `sysctl(KERN_PROC_ALL)` to build parent map for BFS

**Ghostty PID**: Ghostty manages its own PTY so `shellPid` is always 0. `ProcessTreeAnalyzer.findClaudeProcess(in:shellPID:sessionId:)` uses `ProcessInfo.processInfo.processIdentifier` (app PID) as ancestor when `shellPID == 0` — Ghostty forks PTY children directly from the Tenvy process.

**Kill target** (`WindowDelegate`): `runtimeInfo.shellPid` if set, otherwise `runtimeInfo.pid` (the sysctl-discovered claude PID). Both the confirmation dialog gate and the kill use this `pidToKill`.

**Why:** Without this, no PID/MEM stats appeared in the sidebar and closing a session window left the claude process running.

**How to apply:** Any future code that needs process info must use sysctl, not `Process()`/`ps`. Never use `Process()` for process enumeration while Ghostty is embedded.
