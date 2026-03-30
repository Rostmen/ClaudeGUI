---
name: Tenvy project overview
description: Core facts about the Tenvy macOS app project — what it is, stack, repo, distribution
type: project
---

**Tenvy** is a macOS app (Swift/SwiftUI) for managing and resuming Claude Code CLI sessions.

- **Repo**: git@github.com:Rostmen/ClaudeGUI.git
- **Project file**: `Tenvy.xcodeproj` (source folders: `Tenvy/`, `TenvyTests/`, `TenvyUITests/`)
- **Target macOS**: 26.2+ (Tahoe) — deployment target is 26.2
- **Distribution**: Notarized direct download via GitHub Releases (NOT App Store — app spawns shell processes incompatible with App Sandbox)
- **Bundle ID**: `com.kobizsky.tenvy`
- **Team ID**: `AWKHNRR4U2`

**Why:** The app launches `claude` CLI as a subprocess and reads/writes `~/.claude/` — fundamentally incompatible with App Sandbox.
**How to apply:** Never suggest App Store distribution. Always assume direct notarized distribution.
