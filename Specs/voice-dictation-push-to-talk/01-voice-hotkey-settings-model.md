---
name: Voice Hotkey Settings Model
status: done
---

# Summary

Add persisted settings for a user-configurable Dictate hotkey.

# Scope

- Extend `VoiceSettings` with a hotkey value that can round-trip through `UserDefaults`.
- Store the shortcut in a form that maps directly to `HotKey.KeyCombo`:
  - `carbonKeyCode`
  - `carbonModifiers`
- Keep the default shortcut as `Command-Shift-D`.
- Preserve backward compatibility for installs that only have the existing voice settings.

# Acceptance Criteria

- Voice hotkey settings load/save correctly.
- Existing users without a saved voice shortcut fall back to `Command-Shift-D`.
