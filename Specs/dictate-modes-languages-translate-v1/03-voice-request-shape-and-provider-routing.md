---
name: Voice Request Shape And Provider Routing
status: todo
---

# Summary

Carry Dictate language and translation options through the shared voice request model into both providers.

# Scope

- Expand the shared voice task/request payload beyond raw custom instructions.
- Update router dispatch for the richer voice transcription request.
- Update OpenAI and Gemini transcription request builders to use the new prompt API.
- Keep provider/model selection and error handling unchanged.

# Acceptance Criteria

- Both providers receive the same Dictate options through the shared request model.
- Existing Dictate routing behavior remains intact.
- Provider tests cover the new prompt content.

