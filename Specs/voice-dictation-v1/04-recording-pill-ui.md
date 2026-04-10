---
name: Recording Pill UI
status: todo
---

# Summary

Add a bottom-centered floating recording indicator with cancel, confirm, and live level feedback.

# Scope

- Implement a dedicated presenter for a small floating pill window.
- Match the intended v1 states:
  - idle: hidden
  - recording: show cancel button, level meter, and confirm button
  - transcribing: keep the pill visible and switch meter to a busy state
- Keep the UI above normal app windows but below system security UI.
- Support click handlers for:
  - `Cancel` -> discard recording
  - `OK` -> stop recording and submit
- Ensure the presenter can be controlled from a coordinator without view-owned business logic.

# Acceptance Criteria

- The pill appears at the bottom center when recording starts.
- The meter reacts to microphone input while recording.
- `Cancel` and `OK` invoke coordinator-owned actions.
- The pill disappears after cancel, success, or terminal failure.
