---
name: Persistence & Migration
status: done
---

## Summary

Persist dictate modes as JSON in UserDefaults. Migrate legacy `voiceCustomInstructions` into the default mode on first load.

## Scope

**File:** `Sources/Steward/LLMSettings.swift` (`UserDefaultsLLMSettingsStore`)

1. Add new keys to `Keys`:
   - `voiceDictateModes: Defaults.Key<String>` — JSON-encoded `[DictateMode]`, default `""`.
   - `voiceActiveModeID: Defaults.Key<String>` — UUID string, default `""`.

2. Update `loadSettings()`:
   - Attempt to decode `voiceDictateModes` from JSON into `[DictateMode]`.
   - If empty/invalid: check legacy `voiceCustomInstructions`. If non-empty, create `[DictateMode.defaultMode(customInstructions: legacyValue)]`. Otherwise create `[DictateMode.defaultMode()]`.
   - Parse `voiceActiveModeID` into `UUID?`.
   - Pass `modes` and `activeModeID` to `VoiceSettings` init.

3. Update `saveSettings()`:
   - Encode `modes` to JSON, write to `voiceDictateModes`.
   - Write `activeModeID?.uuidString ?? ""` to `voiceActiveModeID`.
   - Clear legacy key: set `voiceCustomInstructions` to `""`.

4. Remove the backward-compat computed `customInstructions` property from `VoiceSettings` (added in spec 01). All callers now use `activeMode.customInstructions`.

## Acceptance Criteria

- [ ] Fresh install: loads single default mode with empty instructions.
- [ ] Existing user with `voiceCustomInstructions = "Be concise"`: migrates into default mode.
- [ ] Multiple modes + active mode ID round-trip through save/load.
- [ ] Legacy `voiceCustomInstructions` cleared after first save.
- [ ] `make test` passes.
