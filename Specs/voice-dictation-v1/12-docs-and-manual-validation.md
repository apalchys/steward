---
name: Docs And Manual Validation
status: todo
---

# Summary

Update user-facing docs and define manual validation scenarios for the final feature.

# Scope

- Update `README.md` with:
  - what voice dictation does
  - the `Command-Shift-D` shortcut
  - microphone permission requirement
  - configurable provider and model behavior
- Add a short manual validation checklist covering:
  - successful dictation into a text field
  - mixed-language dictation
  - cancel flow
  - insertion failure with clipboard fallback
  - missing microphone permission
  - 120-second auto-stop

# Acceptance Criteria

- Setup and usage docs mention the voice feature and its permissions.
- There is a clear manual test list for validating the full workflow before release.
