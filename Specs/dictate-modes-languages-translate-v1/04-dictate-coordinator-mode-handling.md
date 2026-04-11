---
name: Dictate Coordinator Mode Handling
status: todo
---

# Summary

Support separate regular-hotkey toggle behavior while preserving push-to-talk and menu-driven Dictate flows.

# Scope

- Add a dedicated coordinator entrypoint for regular-mode hotkey toggling.
- Keep push-to-talk key-down/key-up behavior unchanged.
- Keep menu-triggered Dictate using the interactive recording pill.
- Ensure translation mode uses the final Dictate output before insertion or clipboard fallback.

# Acceptance Criteria

- Regular Dictate hotkey starts recording on first press and stops/transcribes on second press.
- Push-to-talk release cannot stop a regular/manual session.
- Menu Dictate behavior still works.

