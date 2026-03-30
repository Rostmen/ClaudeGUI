---
name: Process monitoring and termination (Ghostty/sysctl)
description: How Tenvy discovers and kills claude processes; why sysctl replaced ps; Ghostty SIGCHLD deadlock
type: project
---

Ghostty installs a SIGCHLD handler that reaps all child processes — including any `ps` subprocess spawned via `Process()` — before `waitUntilExit()` can observe the exit. This causes a permanent deadlock.

**Fix applied**: replaced all `Process()`/`ps` usage with `sysctl` kernel calls:
- `ProcessPoller` (hot path, 500 ms): `sysctl(KERN_PROC_ALL)` + `KERN_PROCARGS2` + `proc_pidinfo(PROC_PIDTASKINFO)` for PID/PPID/args/RSS/CPU
- `ProcessManager.findChildProcesses` (termination path): same `sysctl(KERN_PROC_ALL)` to build parent map for BFS

**PID discovery**: `SessionStateMonitor` receives a `pidProvider` closure from `GhosttyHostView` that queries `surface.foregroundPid`. This returns the `login` PID (Ghostty's PTY child). The monitor walks down the process tree via `findLeafDescendant(of:in:)` to reach the actual process (`login → claude`). No arg-matching needed (the old `ProcessTreeAnalyzer` was removed — it used substring matching on "claude" in process args, which false-positived on MCP servers and other unrelated processes). Once the leaf PID appears in the snapshot, it's locked in. If the locked PID dies, the provider is re-queried and the leaf walk repeats.

**Kill target** (`WindowDelegate`): `runtimeInfo.shellPid` if set, otherwise `runtimeInfo.pid` (the sysctl-discovered claude PID). Both the confirmation dialog gate and the kill use this `pidToKill`.

**Why:** Without this, no PID/MEM stats appeared in the sidebar and closing a session window left the claude process running.

**How to apply:** Any future code that needs process info must use sysctl, not `Process()`/`ps`. Never use `Process()` for process enumeration while Ghostty is embedded.
