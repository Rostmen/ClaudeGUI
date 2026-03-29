---
description: Rules for keeping project documentation and memory up to date
---

# Documentation Rules

## When to update

Every architecture change, crucial technical finding, or pattern decision MUST be documented immediately as part of the implementation — not as an afterthought.

## What to update

1. **CLAUDE.md** (repo root):
   - Architecture diagram when adding/removing/renaming files
   - "Critical Implementation Details" when adding new patterns or constraints

2. **`.claude/rules/`** — for permanent coding rules, patterns, and constraints that apply across conversations. Create or update a rule file when:
   - User requests a specific pattern (e.g., "use action enums")
   - A technical constraint is discovered (e.g., "SwiftUI .contextMenu doesn't work on NSViewRepresentable subviews")
   - An architectural decision is made that should be followed going forward

3. **`.claude/memory/MEMORY.md`** — index file for project-specific memory. Must stay under 200 lines. Use one-line entries that reference detailed files in `.claude/memory/`:
   - `- [architecture.md](architecture.md) — Terminal view three-layer separation`
   - Detailed findings go in the referenced files, not in MEMORY.md itself

4. **`FEATURES.md`** — when features are added or changed
