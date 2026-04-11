---
name: Dictate Settings UI
status: done
---

# Summary

Add a dedicated Dictate tab to Preferences so the feature can be configured independently.

# Scope

- Add a `Dictate` tab to `SettingsView`.
- Include:
  - provider picker for Gemini vs OpenAI
  - API key entry for the selected provider
  - model field for the selected provider
  - custom instructions editor
  - fixed hotkey display: `Command-Shift-D`
  - short note that v1 is optimized for recordings up to 120 seconds
- Persist changes through the existing settings store and trigger provider re-checks when settings change.

# Acceptance Criteria

- Users can configure Dictate provider, model, and custom instructions independently of Refine and Capture.
- Provider-specific credentials already stored in settings remain reusable in the Dictate tab.
- Changing Dictate settings updates the saved configuration immediately.
