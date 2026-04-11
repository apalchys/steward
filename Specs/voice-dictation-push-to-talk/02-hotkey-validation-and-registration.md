---
name: Hotkey Validation And Registration
status: done
---

# Summary

Validate custom dictation shortcuts and register them dynamically at runtime.

# Scope

- Rework voice hotkey registration to use the persisted voice shortcut instead of a fixed constant.
- Keep Refine and Capture shortcuts fixed.
- Validate a custom voice shortcut before saving or activating it:
  - must include at least one modifier
  - must include a non-modifier key
  - must not conflict with Steward’s fixed Refine or Capture shortcuts
  - must pass the existing global shortcut availability check
- Reject invalid shortcuts and keep the previous working shortcut active.
- Re-register the voice hotkey whenever settings change.

# Acceptance Criteria

- A saved custom voice hotkey becomes active without restarting the app.
- Invalid or conflicting shortcuts are blocked immediately.
