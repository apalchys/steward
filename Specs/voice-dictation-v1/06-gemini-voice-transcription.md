---
name: Gemini Voice Transcription
status: todo
---

# Summary

Teach the Gemini client to transcribe short audio clips for the new voice feature.

# Scope

- Add a Gemini client method for voice transcription.
- Use the existing Gemini API shape with inline audio data and the shared voice prompt.
- Encode `audio/wav` data in the provider request.
- Parse the response into plain text only.
- Surface empty output, request failure, and invalid model errors consistently with the rest of the client.

# Acceptance Criteria

- Gemini voice requests are encoded with inline audio payloads.
- Successful responses return the cleaned transcript text.
- Error handling matches the existing client conventions.
