---
name: Push To Talk Hotkey Flow
status: todo
---

# Summary

Change the global dictation shortcut from toggle behavior to press-and-hold push-to-talk.

# Scope

- Use `keyDownHandler` to start recording for the voice hotkey.
- Use `keyUpHandler` to stop recording and immediately start transcription.
- Treat repeated key-down events while already recording as no-ops.
- Treat key-up while idle or transcribing as a no-op.
- Keep push-to-talk behavior exclusive to the global voice hotkey path.

# Acceptance Criteria

- Holding the voice hotkey records audio.
- Releasing the voice hotkey stops recording and starts transcription.

