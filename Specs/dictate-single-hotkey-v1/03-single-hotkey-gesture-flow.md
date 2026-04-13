---
name: Single Hotkey Gesture Flow
status: todo
---

# Summary

Make one Dictate hotkey support hold-to-talk and per-session sticky recording based on press timing.

# Scope

- Replace separate push-to-talk and regular-hotkey coordinator entrypoints with one key-down path and one key-up path.
- Start Dictate recording immediately on hotkey down while idle.
- Use a `200ms` hold threshold to distinguish a hold from a tap.
- On hotkey up before the hold threshold, keep the recording alive and open a `250ms` double-press window.
- If a second hotkey down arrives inside that window, latch the current recording into sticky mode without restarting the session.
- While latched, stop and transcribe on the next hotkey down.
- Ignore the key-up that follows the stop press for a latched session.
- If no second press arrives before the double-press window expires, cancel the short-tap recording without transcription.
- Reset all Dictate gesture state and timers on cancel, completion, max-duration stop, or error.
- Keep menu-triggered Dictate on its existing manual toggle flow.

# Acceptance Criteria

- Holding the Dictate hotkey records and transcribes on release.
- A quick single tap does not insert text and leaves Dictate idle after the double-press window expires.
- A quick double press latches the active Dictate session without restarting it.
- The next hotkey press after latching stops and transcribes that same session.
- Menu-triggered Dictate remains isolated from hotkey gesture state.
