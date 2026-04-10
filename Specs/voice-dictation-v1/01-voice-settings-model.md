---
name: Voice Settings Model
status: todo
---

# Summary

Add voice-specific persisted settings to the existing app settings model and choose stable defaults for v1.

# Scope

- Extend `LLMSettings` with a `VoiceSettings` value.
- Include:
  - `providerID`
  - `geminiModelID`
  - `openAIModelID`
  - `customInstructions`
- Set defaults:
  - provider: `gemini`
  - Gemini model: `gemini-3.1-flash-lite-preview`
  - OpenAI model: `gpt-4o-mini-transcribe`
  - custom instructions: empty string
- Update `UserDefaultsLLMSettingsStore` load/save paths.
- Preserve backward compatibility for existing installs with no voice keys saved yet.

# Acceptance Criteria

- Existing users load with valid default voice settings.
- Voice settings round-trip through the settings store.
- Grammar, OCR, and clipboard settings behavior does not change.
