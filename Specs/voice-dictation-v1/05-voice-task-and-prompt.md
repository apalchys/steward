---
name: Voice Task And Prompt
status: done
---

# Summary

Extend the shared LLM task model to support voice transcription and define the default cleanup behavior for multilingual dictation.

# Scope

- Add a new `LLMTask.voiceTranscription(audioData:mimeType:customInstructions:)`.
- Add a shared `buildVoiceTranscriptionPrompt(customInstructions:)` helper in `StewardCore`.
- Default prompt behavior must:
  - preserve the spoken language or mix of languages
  - not translate
  - add punctuation, casing, and paragraph structure when helpful
  - return only the final text
- Add any request-model support needed to supply a voice-specific model override without affecting grammar or OCR defaults.

# Acceptance Criteria

- Router request types can represent voice transcription cleanly.
- The default voice prompt is reusable across providers.
- Voice requests can select a feature-specific model independently of other features.
