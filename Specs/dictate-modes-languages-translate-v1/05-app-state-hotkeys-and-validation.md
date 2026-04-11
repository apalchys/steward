---
name: App State Hotkeys And Validation
status: todo
---

# Summary

Register and validate separate Dictate shortcuts for push-to-talk and regular mode.

# Scope

- Register both Dictate shortcuts at app startup and on settings changes.
- Validate each Dictate shortcut against:
  - Refine
  - Capture
  - the other Dictate shortcut
  - global shortcut availability
- Keep menu status, busy-state handling, and shortcut error messaging coherent.

# Acceptance Criteria

- Both Dictate shortcuts activate the intended coordinator entrypoints.
- Conflicting Dictate shortcuts are rejected immediately.
- Existing Refine and Capture shortcut behavior remains unchanged.

