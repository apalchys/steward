---
name: Coordinator Entrypoints
status: done
---

# Summary

Refactor the voice coordinator to support separate push-to-talk and manual-toggle entrypoints.

# Scope

- Extend `DictateCoordinating` with distinct actions for:
  - push-to-talk key down
  - push-to-talk key up
  - manual toggle action
- Track the active recording source:
  - push-to-talk hotkey
  - manual toggle
- Keep microphone permission checks at recording start.
- Keep current transcription request construction and insertion fallback logic intact.

# Acceptance Criteria

- The coordinator can distinguish between hotkey-driven and menu-driven sessions.
- Existing voice provider routing behavior remains unchanged.
