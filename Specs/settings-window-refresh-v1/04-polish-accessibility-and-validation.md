---
name: Polish Accessibility And Validation
status: done
---

# Summary

Polish settings presentation while preserving existing validation and persistence flows.

# Scope

- Keep launch-at-login refresh behavior on app activation.
- Keep settings normalization and persistence unchanged.
- Preserve voice hotkey validation and clipboard destructive confirmation flow.
- Keep text selection enabled for storage path and build metadata where useful.
- Use native controls and system colors for macOS-consistent accessibility.

# Acceptance Criteria

- Settings changes still persist immediately through existing store logic.
- Voice hotkey validation still blocks invalid shortcuts.
- Clipboard history clearing still requires confirmation.
- No new persistence keys or schema changes are introduced.
