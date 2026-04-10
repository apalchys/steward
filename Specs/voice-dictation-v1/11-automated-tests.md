---
name: Automated Tests
status: todo
---

# Summary

Add focused automated coverage for the new voice feature without weakening existing tests.

# Scope

- Add settings migration tests for new voice defaults and round-trip behavior.
- Add coordinator tests for:
  - start recording
  - stop and submit
  - cancel
  - permission denial
  - provider error
  - invalid provider response
  - insertion fallback to clipboard
- Add app state tests for:
  - hotkey registration
  - microphone permission visibility
  - feature locking while voice is active
  - voice provider status updates
- Add provider client tests for Gemini and OpenAI voice request encoding and response parsing.

# Acceptance Criteria

- New voice feature behavior is covered at settings, coordinator, app-state, and provider-client levels.
- Existing test suites continue to pass without changed expectations for grammar, OCR, or clipboard history.
