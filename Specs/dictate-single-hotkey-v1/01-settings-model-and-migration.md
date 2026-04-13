---
name: Settings Model And Migration
status: todo
---

# Summary

Collapse Dictate shortcut settings from two hotkeys into one persisted hotkey with a new default.

# Scope

- Replace `VoiceSettings.pushToTalkHotKey` and `VoiceSettings.regularModeHotKey` with a single `VoiceSettings.hotKey`.
- Set the Dictate default hotkey to `Control-Shift-Space`.
- Keep the existing keyboard and extra-mouse-button storage shape:
  - `triggerKind`
  - `carbonKeyCode`
  - `carbonModifiers`
  - `mouseButtonNumber`
- Read and write only the new single-hotkey Dictate keys.
- Treat existing installs as a forced reset to the new default instead of preserving either legacy Dictate shortcut.
- Clear obsolete Dictate hotkey keys when saving settings so old dual-hotkey values stop affecting future loads.

# Acceptance Criteria

- New installs load Dictate with `Control-Shift-Space`.
- Existing installs upgrade to the same single Dictate default on first load under the new schema.
- Dictate settings round-trip one hotkey value for both keyboard and mouse-button shortcuts.
- No second Dictate hotkey remains in the persisted settings model.
