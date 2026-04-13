---
name: Tests Docs And Regression Coverage
status: done
---

# Summary

Cover the single-hotkey Dictate change with automated tests and updated docs.

# Scope

- Add or update tests for:
  - single-hotkey settings load/save
  - forced migration to `Control-Shift-Space`
  - single Dictate hotkey registration and validation
  - quick tap cancellation
  - hold-to-talk transcription on release
  - double-press latching
  - latched-session stop behavior
  - recording pill mode changes
- Update README Dictate usage and settings descriptions to match the single-hotkey flow.
- Mark related spec tasks done only after implementation and verification finish.

# Acceptance Criteria

- Automated coverage exists for the new Dictate hotkey model and gesture flow.
- README matches the shipped Dictate behavior.
- Related spec files stay `todo` until implementation and checks are complete.
