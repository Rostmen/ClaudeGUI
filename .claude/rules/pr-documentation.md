# PR Documentation Requirements — HARD RULE

Before sending a PR, you MUST perform a thorough documentation audit:

1. **Check all memory files** (`.claude/memory/`) — update any that are outdated or incomplete due to the changes in the PR. Add new memory files for concepts that required manual code exploration.

2. **Check CLAUDE.md** — update the architecture diagram if files were added/removed/renamed. Update "Critical Implementation Details" if new patterns or constraints were introduced.

3. **Check FEATURES.md** — update if features were added, changed, or removed.

4. **Check `.claude/rules/`** — add or update rules if new coding patterns or constraints were established.

5. **Check MEMORY.md** — ensure all new memory files are indexed and stale entries are removed.

6. **Identify gaps** — look for concepts in the code that have NO corresponding documentation. If a future conversation would need to manually explore code to understand a flow, that flow needs a memory file.

This audit is NOT optional. The goal is that future conversations can understand ANY concept by reading memory/docs files rather than manually tracing code paths.
