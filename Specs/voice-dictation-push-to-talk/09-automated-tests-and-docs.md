---
name: Automated Tests And Docs
status: todo
---

# Summary

Cover the new hotkey customization and push-to-talk workflow with tests and update the docs.

# Scope

- Add tests for:
  - voice hotkey settings round-trip
  - shortcut validation and conflict rejection
  - push-to-talk key down / key up behavior
  - manual menu fallback behavior
  - recording pill state differences between push-to-talk and manual mode
  - dynamic hotkey re-registration after settings changes
- Update user-facing docs to explain:
  - custom voice hotkey configuration
  - push-to-talk default behavior
  - menu-item fallback behavior

# Acceptance Criteria

- Automated coverage exists for the new voice hotkey behavior.
- Docs match the shipped push-to-talk interaction model.
