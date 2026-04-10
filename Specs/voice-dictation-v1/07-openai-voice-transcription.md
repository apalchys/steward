---
name: OpenAI Voice Transcription
status: done
---

# Summary

Teach the OpenAI client to transcribe short audio clips for the new voice feature.

# Scope

- Add an OpenAI client method for voice transcription.
- Use the OpenAI transcription endpoint with multipart file upload.
- Send the selected voice model plus the shared voice prompt as transcription guidance.
- Parse the provider response into plain text only.
- Preserve the existing OpenAI error mapping style for invalid credentials, invalid model, network issues, and empty output.

# Acceptance Criteria

- OpenAI voice requests upload recorded audio as multipart form data.
- Successful responses return only the final transcript text.
- Request and response failures are surfaced using the same style as the rest of the client.
