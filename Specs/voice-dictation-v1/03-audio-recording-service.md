---
name: Audio Recording Service
status: todo
---

# Summary

Implement a protocol-backed audio recording service that captures short dictation clips locally and exposes live level updates.

# Scope

- Add a new platform service abstraction for audio recording.
- Implement a live AVFoundation-backed recorder that:
  - records mono audio to a temporary file
  - outputs `audio/wav`
  - publishes input level samples for UI meter animation
  - supports start, stop, and cancel
  - enforces a hard stop at 120 seconds
  - deletes temporary files after completion or cancellation
- Keep the service isolated from routing, UI, and text insertion logic.

# Acceptance Criteria

- Starting recording creates a fresh temporary capture.
- Stopping recording returns audio data plus mime type.
- Canceling recording discards captured audio.
- The service emits enough level updates to drive a simple meter.
- Recording longer than 120 seconds auto-stops cleanly.
