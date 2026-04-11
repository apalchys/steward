---
name: Voice Settings Model And Migration
status: done
---

# Summary

Extend Dictate settings with separate hotkeys, preferred recognition languages, and translate mode fields.

# Scope

- Add persisted Dictate settings for:
  - push-to-talk hotkey
  - regular-mode hotkey
  - up to 5 preferred recognition languages
  - translate mode enabled flag
  - translation target language
- Keep existing installs compatible by migrating the current Dictate hotkey to push-to-talk.
- Provide safe defaults for all new fields.
- Sanitize invalid or out-of-range stored values on load.

# Acceptance Criteria

- Existing users keep their current Dictate shortcut as push-to-talk after upgrade.
- New installs get valid defaults for both Dictate shortcuts.
- Preferred languages persist, dedupe, and cap at 5.
- Translate mode and target language persist correctly.
