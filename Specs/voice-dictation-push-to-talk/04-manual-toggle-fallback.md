---
name: Manual Toggle Fallback
status: done
---

# Summary

Keep a non-hotkey fallback path for dictation so the menu action still works without press-and-hold input.

# Scope

- Preserve the Voice Dictation menu item as a manual toggle fallback.
- Separate manual toggle behavior from push-to-talk hotkey behavior in the coordinator.
- Ensure a key-up event from the global hotkey cannot stop a session started from the menu item.
- Keep the same provider, insertion, and clipboard-fallback behavior across both entry paths.

# Acceptance Criteria

- Menu-triggered dictation can still start and stop without relying on key release.
- Push-to-talk key release only affects hotkey-started sessions.
