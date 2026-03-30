# Memory Location — HARD RULE

ALL memory files MUST be stored in the REPOSITORY at `.claude/memory/`, NOT in `~/.claude/projects/`.

The repo is the single source of truth. When the repo is cloned on another machine, all knowledge must be available.

When creating or updating memory files:
1. Write to `<repo-root>/.claude/memory/<filename>.md`
2. Reference from `<repo-root>/.claude/memory/MEMORY.md`
3. NEVER write to `~/.claude/projects/`
