---
name: App State Hotkey Registration And Validation
status: done
---

# Summary

Register and validate one Dictate hotkey path in app state.

# Scope

- Replace dual Dictate hotkey registration in `AppState` with a single registration flow.
- Keep both key-down and key-up handling for keyboard shortcuts.
- Keep mouse-button shortcut support with matching down and up callbacks.
- Forward the unified Dictate hotkey events to unified coordinator hotkey entrypoints.
- Collapse Dictate shortcut validation into one method.
- Validate the Dictate hotkey against:
  - `Refine`
  - `Capture`
  - external shortcut availability
- Remove Dictate-vs-Dictate conflict handling, duplicate registration messages, and duplicate active-hotkey tracking.

# Acceptance Criteria

- App startup registers one Dictate hotkey.
- Settings changes re-register the current Dictate hotkey without restart.
- Keyboard and mouse Dictate shortcuts both invoke the intended unified hotkey flow.
- Shortcut errors surface as one Dictate registration message instead of separate push-to-talk and regular-mode messages.
