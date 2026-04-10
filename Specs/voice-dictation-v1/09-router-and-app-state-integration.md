---
name: Router And App State Integration
status: todo
---

# Summary

Wire the voice feature into the app lifecycle, hotkey handling, status tracking, and menu actions.

# Scope

- Extend `LLMRouter` to dispatch the new voice task for both providers.
- Add a `voice` feature kind in `AppState`.
- Register fixed shortcut `Command-Shift-D`.
- Add voice provider health checks and status titles.
- Add a new menu action for voice dictation.
- Ensure app-level processing rules prevent grammar, OCR, and voice from running at the same time.
- Reflect active recording and active transcription as processing states in the status bar.

# Acceptance Criteria

- `Command-Shift-D` starts and stops voice dictation.
- Voice provider health can be checked from the app state layer.
- Status bar and menu state stay coherent during recording, transcribing, success, cancel, and failure.
