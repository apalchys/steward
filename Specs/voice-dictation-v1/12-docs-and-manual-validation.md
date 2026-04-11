---
name: Docs And Manual Validation
status: done
---

# Summary

Update user-facing docs and define manual validation scenarios for the final feature.

# Scope

- Update `README.md` with:
  - what Dictate does
  - the `Command-Shift-D` shortcut
  - microphone permission requirement
  - configurable provider and model behavior
- Add a short manual validation checklist covering:
  - successful Dictate insertion into a text field
  - mixed-language Dictate
  - cancel flow
  - insertion failure with clipboard fallback
  - missing microphone permission
  - 120-second auto-stop

# Acceptance Criteria

- Setup and usage docs mention Dictate and its permissions.
- There is a clear manual test list for validating the full workflow before release.

# Manual Validation Checklist

- Dictate success:
  - Focus a text field in another app.
  - Press `Command-Shift-D`, dictate a short sentence, then press `Command-Shift-D` again.
  - Confirm the cleaned-up transcript is inserted at the caret.
- Mixed-language Dictate:
  - Dictate a sentence that mixes two languages.
  - Confirm the output preserves the spoken languages instead of translating them.
- Cancel flow:
  - Start Dictate, speak briefly, then click `Cancel`.
  - Confirm no provider request is made and no text is inserted.
- Clipboard fallback:
  - Force text insertion to fail or test against a non-editable target.
  - Confirm the transcript is copied to the clipboard and the app surfaces an insertion error.
- Missing microphone permission:
  - Revoke Microphone access in System Settings.
  - Start Dictate and confirm the app fails immediately with a microphone-permission error.
- Maximum duration:
  - Record until the 120-second cap is reached.
  - Confirm Steward auto-stops recording, transcribes, and completes the same insertion flow.
