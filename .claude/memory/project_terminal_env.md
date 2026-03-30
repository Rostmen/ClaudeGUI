---
name: Terminal environment and shell sourcing
description: How Tenvy sources ~/.zshrc env vars for the claude process, and custom env var settings
type: project
---

Claude is launched **through the user's login shell** so `~/.zprofile` and `~/.zshrc` are sourced:

```
zsh -l -c '[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc" 2>/dev/null; exec /path/to/claude [args]'
```

**Why not `-i` flag**: `-i` triggers `/etc/zshrc` terminal key-binding setup which fails without a proper TTY, producing errors like `kf1: parameter not set`.

**Why `exec`**: replaces the shell with claude at the same PID — SwiftTerm's process tracking (shellPid, CPU monitoring, termination) is unaffected.

**`LANG=en_US.UTF-8`**: set explicitly if missing — GUI apps launched by launchd don't inherit it, and `/etc/zprofile` line 6 fails without it.

**Custom env vars**: stored in `AppSettings.customEnvironmentVariables: [String: String]` (JSON in macOS Keychain, service `com.rostmen.Tenvy`, account `environmentVariables`). Applied in `TerminalEnvironment.build()` after LANG and TERM vars. Managed via Settings → Environment Variables section. Migrated from UserDefaults on first launch.

**How to apply:** If claude asks to login despite being logged in system terminal, check: shell is sourcing .zshrc (the `source` line), LANG is set, relevant auth token is in .zprofile or .zshrc (not .zshenv only).
