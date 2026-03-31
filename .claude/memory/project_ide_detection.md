---
name: IDE Detection & Open In
description: How IDEDetectionService detects project type and installed IDEs, IDEHeaderButton in pane header, NSWorkspace bundle ID lookup
type: project
---

# IDE Detection & "Open in IDE"

Detects project type from files in the project directory and matches against installed IDEs on the system. Shows an icon button in the pane header (Claude sessions only, not plain terminals).

**Why:** Users work on projects that map to specific IDEs. One-click opening saves context-switching friction.

**How to apply:** IDE catalog is in `IDEDetectionService.knownIDEs`. To add a new IDE, append an `IDEDefinition` with the correct bundle identifier and indicator patterns.

## Key Files

- `Tenvy/Features/IDE/IDEDetectionService.swift` — Models (`IDEDefinition`, `DetectedIDE`, `IDEDetectionResult`) + stateless detection service
- `Tenvy/Features/Terminal/PaneHeader/IDEHeaderButton.swift` — Pane header button with optional dropdown for multiple IDEs

## Detection Flow

1. List immediate children of `session.projectPath` (falls back to `workingDirectory`)
2. For each `IDEDefinition` in catalog: check installed via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`, match indicators against children
3. Project-specific IDEs (e.g. Xcode for `.xcodeproj`) only shown when indicators match; general-purpose editors (VS Code, Cursor, Zed, etc.) always shown when installed
4. Results cached per path on `ContentViewModel.ideDetectionCache` — avoids re-scanning on focus changes

## IDE Installed Detection

Uses `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` — queries Launch Services database. Works regardless of install location. Icons loaded via `NSWorkspace.shared.icon(forFile: appURL.path)`.

## Header Button

- `IDEHeaderButton` in pane header, between title and close button
- Single IDE → plain icon button; multiple IDEs → icon + Menu chevron dropdown
- Only shown for Claude sessions (`!viewModel.isPlainTerminal`)
- `PaneHeaderDragSourceNSView.trailingInset` expands dynamically when IDE button is present so the drag hand cursor doesn't cover the button area

## Supported IDEs

Project-specific: Xcode, Android Studio, IntelliJ IDEA, RustRover, Rider, GoLand, WebStorm, RubyMine, PyCharm
General-purpose: VS Code, Cursor, Windsurf, Zed, Sublime Text, Nova, Fleet
