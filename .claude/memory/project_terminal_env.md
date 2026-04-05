---
name: Terminal environment and shell sourcing
description: Configurable shell init script, per-split overrides, env vars, and how Tenvy launches terminal processes
type: project
---

Claude is launched **through the user's login shell** with a configurable init script:

```
zsh -l -c '<init-script>; exec /path/to/claude [args]'
```

**Shell Init Script**: Configurable in Settings → Shell Init Script using CodeEditor (bash syntax highlighting). Default: `[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null;`. Stored in `AppSettings.shellInitScript` (UserDefaults key `settings.shellInitScript`).

**Per-split override**: The unified NewSessionDialogView has a "Shell Init Script" tab allowing per-session init script customization. Overrides are stored in `ContentViewModel.splitInitScripts` (keyed by tenvySessionId) and consumed on first terminal launch.

**`TerminalEnvironment.shellArgs()` and `.plainShellArgs()`**: Both accept optional `initScript:` parameter. Falls back to global `AppSettings.shared.shellInitScript` when nil.

**Why not `-i` flag**: `-i` triggers `/etc/zshrc` terminal key-binding setup which fails without a proper TTY, producing errors like `kf1: parameter not set`.

**Why `exec`**: replaces the shell with claude at the same PID — process tracking (shellPid, CPU monitoring, termination) is unaffected.

**`LANG=en_US.UTF-8`**: set explicitly if missing — GUI apps launched by launchd don't inherit it, and `/etc/zprofile` line 6 fails without it.

**Custom env vars**: stored in `AppSettings.customEnvironmentVariables: [String: String]` (JSON in macOS Keychain, service `com.rostmen.Tenvy`, account `environmentVariables`). Applied in `TerminalEnvironment.build()` after LANG and TERM vars. Managed via Settings → Environment Variables section.

**Migration**: Old `sourceZshrc` boolean setting is automatically migrated to the new `shellInitScript` string format.
