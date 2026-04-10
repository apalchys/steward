---
name: App State And Menu Integration
status: todo
---

# Summary

Wire the configurable push-to-talk dictation shortcut through app state, menu status, and settings refresh.

# Scope

- Update `AppState` to register voice hotkeys with both key-down and key-up handlers.
- Refresh the active voice hotkey when settings change.
- Remove the hard-coded voice menu keyboard shortcut because the global combo is now configurable.
- Keep status bar behavior coherent during:
  - push-to-talk recording
  - transcribing after release
  - manual menu fallback recording

# Acceptance Criteria

- The app menu reflects the feature without showing a stale fixed keyboard shortcut.
- Status titles and busy-state behavior remain correct for both voice entry paths.

