---
name: Memory files must live in the repository
description: HARD RULE — all memory/knowledge files go in the repo (.claude/memory/), never in ~/.claude/projects/
type: feedback
---

ALL memory files MUST be stored in the REPOSITORY at `.claude/memory/`, NOT in `~/.claude/projects/`. The repo is the single source of truth. If the repo is cloned on another machine, all knowledge must be available.

**Why:** User lost all knowledge base when pulling on a different computer because memories were in the user-local `~/.claude/projects/` path instead of checked into the repo.

**How to apply:** When creating or updating memory files, always write to `<repo-root>/.claude/memory/` and reference them from `<repo-root>/.claude/memory/MEMORY.md`. Never write memory files to `~/.claude/projects/`.
