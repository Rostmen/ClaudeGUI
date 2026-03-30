---
name: Git commit and push rules
description: User requires explicit approval before any git commit or push
type: feedback
---

Never commit or push without the user explicitly saying "commit and push" or similar approval.

**Why:** User wants to test/verify changes before they go to git history and trigger CI.
**How to apply:** After making code changes, stop and wait. Only run `git commit` + `git push` when the user explicitly asks (e.g. "okay commit and push", "commit and push", "yes").
