---
name: Dictate Coordinator
status: done
---

# Summary

Add a coordinator that owns the full voice workflow from permission check through final insertion.

# Scope

- Introduce `DictateCoordinator` following the same architectural role as the refine and Capture coordinators.
- Responsibilities:
  - check microphone permission before recording
  - start and stop the audio recording service
  - drive the recording pill presenter
  - submit the final audio to `LLMRouter`
  - insert the transcript into the focused text field
  - fall back to clipboard copy if insertion fails
- Expose coordinator actions for:
  - first hotkey press: start recording
  - second hotkey press: stop and transcribe
  - cancel from UI
  - confirm from UI
- Define and use voice-specific error cases for permission denial, cancellation, empty audio, invalid provider response, and insertion fallback.

# Acceptance Criteria

- Starting Dictate opens a new recording session.
- Stopping or confirming sends one provider request and inserts the result.
- Canceling ends the session without sending audio.
- Failed insertion copies the transcript to the clipboard instead of losing it.
