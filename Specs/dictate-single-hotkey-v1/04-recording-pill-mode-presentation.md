---
name: Recording Pill Mode Presentation
status: done
---

# Summary

Show the correct Dictate pill presentation as the single hotkey moves between hold and sticky behavior.

# Scope

- Keep passive pill presentation while Dictate is in hold-to-talk mode.
- Switch the active session to the interactive pill as soon as double-press latches sticky recording.
- Keep menu-triggered Dictate using the interactive pill from the start.
- Preserve the existing transcribing presentation.
- Ensure cancel, completion, max-duration stop, and error flows hide the pill and clear any mode-specific presentation state.

# Acceptance Criteria

- Hold-to-talk Dictate shows the passive pill with no confirm/cancel controls.
- A latched hotkey session switches to the interactive pill without restarting the recording.
- Menu Dictate still shows the interactive pill.
- The pill returns to hidden when Dictate finishes, cancels, or fails.
