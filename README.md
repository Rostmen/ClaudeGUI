# Tenvy

**Tenvy** is a native macOS app for managing and resuming [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) CLI sessions — with a beautiful glass UI, embedded terminal, and smart notifications.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat-square)
![License](https://img.shields.io/github/license/Rostmen/ClaudeGUI?style=flat-square)
![Release](https://img.shields.io/github/v/release/Rostmen/ClaudeGUI?style=flat-square)

---

## Features

### Session Management
Browse all your Claude Code sessions in one place. Resume any session instantly, rename sessions for easier identification, and delete ones you no longer need. Sessions are discovered automatically from `~/.claude/projects/`.

### Embedded Terminal
Each session runs in a full terminal embedded directly in the app — choose between **SwiftTerm** (default) or **Ghostty** in Settings. Every session gets its own isolated window or tab — no cross-contamination between projects. Tenvy monitors CPU usage to detect when Claude is thinking, waiting, or idle, and reflects that state in real time.

### Smart Notifications
Tenvy hooks into Claude Code's event system to notify you when:
- **Claude is waiting for your input** — get a macOS notification when a background session needs attention
- **Permission is required** — approve or deny tool use directly from the notification without switching windows

Notifications are suppressed for the session you're actively viewing and shown only for background sessions.

### Git Changes
See which files Claude modified at a glance. The Git Changes tab shows a tree of modified, added, and deleted files with syntax-highlighted diffs — so you can review Claude's work without leaving the app.

### Appearance
Choose between **Light**, **Dark**, or **System** (follows macOS) in **Settings → Appearance**. Tenvy applies the chosen mode across all windows — including the Settings and Release Notes windows — and automatically syncs the Claude CLI theme in `~/.claude.json` so Claude's output colors match. Idle sessions are restarted transparently so the new theme takes effect immediately.

### Glass UI
Tenvy uses a transparent vibrancy window with an overlay that cuts out around the terminal — keeping the terminal crisp and readable while the rest of the app blends into your desktop. The overlay adapts to the selected appearance mode.

### Multi-Window Support
Open multiple Claude Code sessions side by side, each in its own window or tab. Tenvy enforces one process per session — no duplicate terminals, no wasted resources.

### Automatic Updates
Tenvy checks for new versions on every launch. When an update is available, a prompt appears in the bottom-right corner. Click **Update** and Tenvy installs the new version silently in the background via Homebrew, then relaunches automatically — no Terminal window, no manual steps.

### Shell Environment
Tenvy sources your `~/.zprofile` and `~/.zshrc` before launching Claude, so auth tokens, PATH entries, and other shell exports are available just as they are in your regular terminal. You can also add custom environment variables in **Settings → Environment Variables**.

---

## Requirements

- macOS 26 (Tahoe) or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview) installed

---

## Installation

### Homebrew (recommended)

```bash
brew install --cask rostmen/tenvy/tenvy
```

### Manual

1. Download the latest `Tenvy-x.x.x.dmg` from [Releases](https://github.com/Rostmen/ClaudeGUI/releases)
2. Open the DMG and drag **Tenvy** to your Applications folder
3. Launch Tenvy from Applications

> Tenvy is notarized by Apple — no "unidentified developer" warnings.

---

## Setup

On first launch, Tenvy will prompt you to install Claude Code hooks. These hooks allow Tenvy to track session state and send notifications. Click **Install Hooks** when prompted — it takes one second and requires no manual steps.

---

## Building from Source

```bash
git clone https://github.com/Rostmen/ClaudeGUI.git
cd ClaudeGUI
open Tenvy.xcodeproj
```

Or from the command line:

```bash
xcodebuild -scheme Tenvy -destination 'platform=macOS'
```

**Requirements**: Xcode 17+, macOS 26 SDK

---

## License

MIT — see [LICENSE](LICENSE)
