---
name: Settings UI & Pill Update
status: done
---

## Summary

Update the Dictate settings pane with a modes editor. Show active mode name in the recording pill and menu bar status.

## Scope

### Settings UI
**File:** `Sources/Steward/SettingsView.swift`

1. Replace single "Custom Instructions" editor with a "Modes" section inside `dictateControlsCard`.
2. Mode list — each mode rendered as a card:
   - Green dot if active mode.
   - Editable name `TextField`.
   - Expand/collapse disclosure for custom instructions `TextEditor`.
   - Delete button (disabled for default mode).
   - Tap row or button to set as active.
3. "Create Mode" button at bottom of list. New modes get name "Mode N".
4. Add `HotKeyRecorderView` for mode switch hotkey, label "Mode Switch Key", after existing dictate hotkey recorder.
5. Mode management helpers: `addMode()`, `deleteMode(id:)`, index-based bindings for name/instructions.

### Pill UI
**File:** `Sources/Steward/VoiceRecordingPill.swift`

6. Add `var modeName: String?` to `VoiceRecordingPillViewModel`.
7. Show mode name as small label/badge inside the pill when `modeName` is non-nil and not "Default".
8. Update `VoiceRecordingPillPresenting` — add `modeName` parameter to `showInteractiveRecording` and `showPassiveRecording`, or add `setModeName(_:)` method.

### Coordinator
**File:** `Sources/Steward/DictateCoordinator.swift`

9. Read active mode name from settings and pass to pill presenter when showing recording state.

### Menu Bar
**File:** `Sources/Steward/AppShell.swift`

10. Update `activityStatusTitle`:
    - Recording: "Status: Listening (ModeName)..." when mode name is not "Default".
    - Transcribing: "Status: Transcribing (ModeName)..." when mode name is not "Default".

## Acceptance Criteria

- [ ] Settings lists all modes with name/instructions editing.
- [ ] Default mode cannot be deleted.
- [ ] New modes can be created via "Create Mode" button.
- [ ] Active mode visually indicated with green dot.
- [ ] Mode switch hotkey configurable in settings.
- [ ] Pill shows active mode name during recording (hidden for "Default").
- [ ] Menu bar status includes mode name during dictation (hidden for "Default").
- [ ] `make build` compiles clean.
- [ ] `make test` passes.
