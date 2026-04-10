---
name: Microphone Permissions
status: todo
---

# Summary

Add microphone permission support so voice capture can be checked, requested, and surfaced consistently with the existing Accessibility and Screen Recording flows.

# Scope

- Add `NSMicrophoneUsageDescription` to `Info.plist`.
- Extend `AppSystemServices` with:
  - current microphone permission status
  - action to open Microphone privacy settings
- Extend `AppState` published state and derived menu titles for microphone permission.
- Include microphone permission in the menu permission section when not granted.
- Decide and implement the workflow boundary:
  - permission must be checked before recording starts
  - denied access should fail early without showing a recording session

# Acceptance Criteria

- Steward can detect whether microphone permission is granted.
- A denied microphone state is visible from the menu bar UI.
- Users can jump to System Settings for Microphone access from the app.
