---
name: Voice Language Catalog And Prompts
status: done
---

# Summary

Add a fixed Dictate language catalog and include selected language/translation preferences in voice prompts.

# Scope

- Define a fixed shared catalog of 25 popular languages with stable IDs and user-facing names.
- Update voice prompt helpers to accept:
  - preferred recognition languages
  - translate mode flag
  - translation target language
  - custom instructions
- Preserve current transcription behavior when no language or translation preferences are set.

# Acceptance Criteria

- Prompt helpers include recognition language hints when languages are selected.
- Translate mode changes the output instruction to translation-only in the chosen language.
- Empty language selection keeps current auto-detect behavior.
