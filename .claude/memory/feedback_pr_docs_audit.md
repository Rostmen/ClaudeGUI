---
name: PR documentation audit required
description: Before sending any PR, perform a thorough audit of all memory files, CLAUDE.md, FEATURES.md, and rules for outdated or missing docs
type: feedback
---

Before sending a PR, always audit all documentation for completeness and accuracy.

**Why:** User found that concepts requiring manual code exploration (tracing signal paths, understanding data flow) should be pre-documented so future conversations don't waste time re-discovering them. Every flow that touches multiple files should have a memory file.

**How to apply:** Follow the full checklist in `.claude/rules/pr-documentation.md`. Key principle: if a future conversation would need to manually `grep`/`Read` through code to understand a concept, that concept needs a memory file. This is a blocking requirement before any PR.
