---
name: Always document architecture changes
description: Every architecture change must update CLAUDE.md and relevant memory files — never let findings go undocumented
type: feedback
---

Every time we change architecture concepts, add new patterns, or discover important technical findings, update documentation immediately.

**Why:** The user explicitly requires institutional memory for this project. Undocumented decisions get lost across conversations, leading to repeated mistakes and wasted time.

**How to apply:**
- Update CLAUDE.md architecture diagram when adding/removing/renaming files
- Update CLAUDE.md "Critical Implementation Details" when adding new patterns or constraints
- Create/update memory files for non-obvious findings (e.g., why a certain approach doesn't work)
- Keep MEMORY.md index under 200 lines — use references to separate .md files for details
- Do this AS PART of the implementation, not as an afterthought
