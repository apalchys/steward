---
name: Mode Picker Overlay
status: done
---

## Summary

Build a floating panel UI for switching between dictate modes at runtime. Follows the same controller + protocol-backed window pattern as `VoiceRecordingPillController`.

## Scope

**New file:** `Sources/Steward/DictateModePicker.swift`

1. Define `DictateModePickerPresenting` protocol:
   ```swift
   @MainActor
   protocol DictateModePickerPresenting: AnyObject {
       var onModeSelected: ((UUID) -> Void)? { get set }
       var onDismissed: (() -> Void)? { get set }
       func show(modes: [DictateMode], activeModeID: UUID)
       func hide()
   }
   ```

2. Define `DictateModePickerWindowing` protocol (same pattern as `VoiceRecordingPillWindowing`).

3. `DictateModePickerController`:
   - Owns NSPanel via protocol-backed window factory.
   - Panel: borderless, non-activating, `.statusBar` level, positioned at screen bottom center.
   - Installs `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` on `show()`, removes on `hide()`.

4. `DictateModePickerViewModel: ObservableObject`:
   - `@Published var modes: [DictateMode]`
   - `@Published var highlightedIndex: Int`
   - `var activeModeID: UUID`
   - Methods: `moveUp()`, `moveDown()`, `selectHighlighted()`, `selectByNumber(_:)`

5. `DictateModePickerView` (SwiftUI):
   - Dark rounded-rect background matching pill aesthetic.
   - Vertical list of rows. Each row: green dot (if active), mode name, number label (1-9 for first 9 modes).
   - Highlighted row has subtle white background.

6. Keyboard handling:
   - Arrow Up/Down — navigate highlighted row.
   - Enter/Return — select highlighted mode, fire `onModeSelected`.
   - Escape — dismiss, fire `onDismissed`.
   - Number keys 1-9 — jump to mode at that index, fire `onModeSelected`.

## Acceptance Criteria

- [ ] Panel appears centered at screen bottom.
- [ ] Modes listed vertically; active mode has green dot indicator.
- [ ] Arrow keys navigate highlight, Enter selects, Escape dismisses.
- [ ] Number keys 1-9 select mode at corresponding index.
- [ ] `onModeSelected` fires with correct UUID on selection.
- [ ] `onDismissed` fires on Escape.
- [ ] Panel hides after selection or dismissal.
- [ ] `make test` passes.
