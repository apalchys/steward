---
name: Hotkey & AppState Integration
status: done
---

## Summary

Add a configurable mode-switch hotkey, register it in AppState, and wire mode selection to persistence.

## Scope

**File:** `Sources/Steward/LLMSettings.swift`
1. Add `modeSwitchHotKey: AppHotKey?` to `VoiceSettings` (optional — nil = no hotkey).
2. Add persistence keys: `voiceModeSwitchHotKeyTriggerKind`, `voiceModeSwitchHotKeyCode`, `voiceModeSwitchHotKeyModifiers`, `voiceModeSwitchHotKeyMouseButtonNumber`.
3. Load/save the optional hotkey (empty trigger kind string = nil).

**File:** `Sources/Steward/AppHotKeyValidation.swift`
4. Validate mode switch hotkey doesn't conflict with refine, capture, or dictate hotkeys.

**File:** `Sources/Steward/AppShell.swift`
5. Add to `AppState`:
   - `private var modeSwitchHotKey: HotKey?`
   - `private var modeSwitchMouseButtonMonitor: (any MouseButtonShortcutMonitoring)?`
   - `private let modePickerPresenter: any DictateModePickerPresenting` (injected via init)
   - `@Published private(set) var activeDictateModeName: String?`
6. Register mode switch hotkey in `setupHotKeys()` / alongside dictate hotkey registration.
7. Mode switch hotkey handler:
   - If dictation idle → load modes from settings, call `modePickerPresenter.show(modes:activeModeID:)`.
   - If recording/transcribing → ignore.
8. Wire `modePickerPresenter.onModeSelected`:
   - Update `settings.voice.activeModeID`, persist via `settingsStore.saveSettings()`.
   - Update `activeDictateModeName`.
   - Call `modePickerPresenter.hide()`.
9. Wire `modePickerPresenter.onDismissed` → `modePickerPresenter.hide()`.

**File:** `Sources/Steward/Steward.swift`
10. Pass `DictateModePickerController()` to `AppState` init.

## Acceptance Criteria

- [ ] Mode switch hotkey configurable and persisted.
- [ ] Pressing hotkey when idle shows mode picker.
- [ ] Pressing hotkey during recording/transcribing is ignored.
- [ ] Selecting a mode persists `activeModeID` and updates `activeDictateModeName`.
- [ ] Escape dismisses picker without changing mode.
- [ ] Hotkey validation prevents conflicts with other app shortcuts.
- [ ] `make test` passes.
