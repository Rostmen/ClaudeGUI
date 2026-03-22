# ChatSessions

macOS app for managing and resuming Claude Code CLI sessions with a native transparent UI.

<!-- waiting state test 2 -->

> **Full Documentation**: See [FEATURES.md](./FEATURES.md) for comprehensive feature documentation, architecture details, and implementation specifics.

## Quick Overview

- **Session Management**: Browse, resume, rename, and delete Claude Code sessions
- **Embedded Terminal**: SwiftTerm-based terminal with CPU-based state monitoring
- **Multi-Window Support**: Each session runs in isolated window/tab with single process
- **File Browser**: Project files with git status indicators
- **Git Changes**: Modified files tree with syntax-highlighted diffs
- **Glass UI**: Transparent window with dark overlay

## Architecture

```
ChatSessions/
├── App/                            # App entry & shared state
│   ├── ChatSessionsApp.swift       # App entry + AppDelegate + WindowAccessor
│   ├── AppState.swift              # Shared singleton (sessions, runtime, registry)
│   ├── ContentView.swift           # Main layout (UI only)
│   └── ContentViewModel.swift      # Session selection & window coordination
├── Features/
│   ├── Session/                    # Session management
│   │   ├── ClaudeSession.swift     # Session data model
│   │   ├── SessionManager.swift    # Discovery & FSEvents monitoring
│   │   ├── SessionListView.swift   # Session list with local selection
│   │   └── SessionRowView.swift    # Session row with status dot
│   ├── Terminal/                   # Terminal & process management
│   │   ├── SessionRuntimeState.swift  # Per-session runtime info (@Observable)
│   │   ├── ProcessManager.swift    # Process tracking & cleanup
│   │   ├── TerminalView.swift      # SwiftTerm wrapper + state monitoring
│   │   ├── EmptyTerminalView.swift # Empty state placeholder
│   │   ├── ClaudePathResolver.swift   # Finds claude CLI binary
│   │   ├── TerminalEnvironment.swift  # Terminal env var configuration
│   │   └── ProcessTreeAnalyzer.swift  # Process tree analysis
│   ├── FileTree/                   # File browser
│   │   ├── FileItem.swift          # File tree item model
│   │   ├── FileTreeCache.swift     # Cached file tree loading
│   │   ├── FileTreeView.swift      # File browser with expansion persistence
│   │   ├── FileTreeNode.swift      # Recursive tree node
│   │   ├── FileRowView.swift       # File row with icon and status
│   │   ├── FileEditorView.swift    # Syntax-highlighted file viewer
│   │   └── ExpansionStateManager.swift  # Tree expansion state persistence
│   ├── Git/                        # Git integration
│   │   ├── GitChangedFile.swift    # Git changed file model
│   │   ├── GitStatusService.swift  # Git status detection
│   │   ├── GitChangesService.swift # Git tree loading & diff fetching
│   │   ├── GitChangesView.swift    # Git changes tree view
│   │   ├── GitChangedFileTreeNode.swift  # Recursive tree node
│   │   ├── GitChangedFileRow.swift # Git file row
│   │   └── DiffView.swift          # Git diff viewer
│   └── Settings/                   # Settings
│       ├── AppSettings.swift       # User preferences (UserDefaults)
│       └── SettingsView.swift      # App preferences view
├── Shared/                         # Shared components
│   ├── WindowSessionRegistry.swift # Window-session mapping
│   ├── SessionGroupingService.swift # Session grouping & filtering
│   ├── SidebarView.swift           # Tabbed sidebar
│   ├── SidebarTab.swift            # Sidebar tab enum
│   ├── SidebarTabBar.swift         # Tab bar picker
│   ├── SidebarTabButton.swift      # Individual tab button
│   ├── NoSessionSelectedView.swift # Empty state for file/changes tabs
│   └── ClaudeTheme.swift           # Theme colors + ANSI palette
└── Resources/
    └── Assets.xcassets
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator |
| [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) | Syntax highlighting |
| [gitdiff](https://github.com/tornikegomareli/gitdiff) | Diff rendering |

## Building

```bash
xcodebuild -scheme ChatSessions -destination 'platform=macOS'
```

Or open in Xcode and press Cmd+R.

## Critical Implementation Details

### Multi-Window Process Isolation

Each session has exactly ONE process. Prevention mechanisms:

1. **WindowSessionRegistry**: Maps window → session
2. **NSWindow.sessionId**: Associated object fallback
3. **AppState.activatedSessions**: Tracks active terminals
4. **Terminal render condition**: `windowConfigured && currentWindow?.sessionId == session.id`

### Session State Monitoring

CPU-based state detection (like ClaudeCodeMonitor):
- `> 25% CPU` → thinking (yellow)
- `< 3% CPU` → waiting (green)
- Rolling 3-sample average, 0.5s polling

### Process Cleanup

Shell PID (not Claude PID) is used for termination:
- Killing shell terminates entire process tree
- Signal handlers: SIGTERM, SIGINT, SIGHUP
- Fallback: `atexit` handler

---

## SwiftUI Coding Conventions

### One View Per File

Each SwiftUI view should have its own dedicated file with a `#Preview` macro:

```swift
// ✅ Good: MyCustomView.swift
struct MyCustomView: View {
  var body: some View { ... }
}

#Preview {
  MyCustomView()
}
```

**Exceptions** (views that can stay in the same file):
- Tiny helper views used only by the parent view (e.g., `private struct`)
- Enum-based tab definitions with their view extensions
- Views that are tightly coupled and always used together

**When to extract:**
- View is reusable across multiple files
- View has its own state or logic worth testing
- View would benefit from isolated `#Preview` testing
- File exceeds ~200 lines

### Preview Guidelines

- Every public view file must have at least one `#Preview`
- Use named previews for multiple states: `#Preview("Selected State") { ... }`
- Include realistic sample data in previews
- Test both light and dark appearances when relevant

---

## Claude Code Workflow Rules

**Git commits and pushes:**
- **DO NOT** commit or push until the user explicitly verifies the changes are good
- Always wait for user approval before running `git commit` or `git push`
- Show the user what changed and let them test/review first

---

## Maintenance Notes

<!-- Last updated: 2026-03-22 -->

**IMPORTANT**: Keep documentation updated when making changes:

- Update [FEATURES.md](./FEATURES.md) for feature changes
- Update architecture diagram when adding/removing files
- Update dependencies when adding new packages
- Document any breaking changes or migration steps
