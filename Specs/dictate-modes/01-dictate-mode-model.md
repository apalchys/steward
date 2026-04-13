---
name: DictateMode Model
status: done
---

## Summary

Define the `DictateMode` data model and integrate it into `VoiceSettings`, replacing the flat `customInstructions` string with a list of named modes.

## Scope

**File:** `Sources/Steward/LLMSettings.swift`

1. Define `DictateMode` struct:
   ```swift
   struct DictateMode: Equatable, Identifiable, Codable {
       let id: UUID
       var name: String
       var customInstructions: String
       var isDefault: Bool
   }
   ```
   Add `static func defaultMode(customInstructions:) -> DictateMode` factory.

2. Add to `VoiceSettings`:
   - `var modes: [DictateMode]` — list of all modes.
   - `var activeModeID: UUID?` — currently active mode.

3. Add computed `activeMode: DictateMode` — returns mode matching `activeModeID`, falls back to first mode.

4. Remove stored `customInstructions` property. Replace with computed property delegating to `activeMode.customInstructions` (temporary backward compat until persistence is updated in spec 02).

5. Update `VoiceSettings.init` — accept `modes` and `activeModeID`, defaulting to `[DictateMode.defaultMode()]` and `nil`.

6. Update `sanitized()` — ensure at least one mode with `isDefault: true` exists; ensure `activeModeID` points to a valid mode (reset to nil if not found).

7. Update `==` to include `modes` and `activeModeID`.

## Acceptance Criteria

- [ ] `DictateMode` is `Equatable`, `Identifiable`, `Codable`.
- [ ] `VoiceSettings` always has at least one default mode after sanitization.
- [ ] `activeMode` never crashes — returns default mode when `activeModeID` is nil or invalid.
- [ ] Existing code compiles without changes via backward-compat `customInstructions` computed property.
- [ ] `make test` passes.
