---
name: Dictate Settings UI
status: done
---

# Summary

Expose new Dictate mode, language, and translation settings in Preferences using existing UI patterns.

# Scope

- Add rows for push-to-talk and regular Dictate shortcuts.
- Add preferred language selection UI with add/remove controls capped at 5 entries.
- Add translate mode toggle and target-language picker.
- Keep model selection and custom instructions in the existing Dictate settings card.
- Surface invalid or incomplete Dictate settings without breaking current preferences behavior.

# Acceptance Criteria

- Users can configure both Dictate shortcuts.
- Users can add up to 5 preferred languages from the fixed catalog.
- Enabling translate mode requires selecting a target language.
