---
name: Settings UI And Copy
status: todo
---

# Summary

Update the Dictate settings surface to describe and configure the new single-hotkey behavior.

# Scope

- Replace the separate `Push To Talk Key` and `Dictate Key` rows with one `Dictate Key` recorder.
- Point restore/default behavior to `Control-Shift-Space`.
- Add help copy that explains:
  - hold to record
  - release after holding to transcribe
  - quick double press to latch sticky recording
  - next press to stop and transcribe
- Keep Dictate model, language, translation, and custom-instructions controls unchanged.
- Keep Dictate shortcut validation feedback attached to the single recorder row.

# Acceptance Criteria

- Preferences shows one Dictate shortcut control.
- Restoring the default sets the Dictate shortcut to `Control-Shift-Space`.
- Settings copy matches the shipped single-hotkey interaction model.
- Dictate shortcut validation still blocks invalid or unavailable shortcuts.
