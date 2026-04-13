---
name: Coordinator Uses Active Mode
status: done
---

## Summary

Update `DictateCoordinator` to read custom instructions from the active dictate mode instead of the removed flat field.

## Scope

**File:** `Sources/Steward/DictateCoordinator.swift`

1. In `voiceTranscriptionConfiguration()`, change:
   ```swift
   customInstructions: voiceSettings.customInstructions
   ```
   to:
   ```swift
   customInstructions: voiceSettings.activeMode.customInstructions
   ```

No changes needed to `VoiceTranscriptionOptions` or `buildVoiceTranscriptionPrompt` in StewardCore.

## Acceptance Criteria

- [ ] Active mode's instructions are passed to `VoiceTranscriptionOptions`.
- [ ] Empty instructions in active mode behaves identically to current empty-instructions behavior.
- [ ] `make test` passes.
- [ ] `make build` compiles clean.
