---
name: Settings UI Consumer Update
status: done
---

# Summary

Keep current settings behavior while switching catalog internals.

# Scope

- Keep provider cards driven by derived catalog entries.
- Keep feature pickers driven by compatible derived entries.
- Keep capability summaries unchanged.
- Keep feature-level selection persistence and sanitization unchanged.

# Acceptance Criteria

- Providers pane still lists provider models and capability summaries.
- Refine Capture Dictate pickers still show only enabled compatible models.
- No new default badges or picker UX changes ship.
- Settings sanitization uses explicit catalog defaults.
