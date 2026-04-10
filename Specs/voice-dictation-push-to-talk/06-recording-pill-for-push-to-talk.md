---
name: Recording Pill For Push To Talk
status: done
---

# Summary

Adjust the floating recording UI so push-to-talk uses a passive indicator instead of confirmation buttons.

# Scope

- Add a recording-pill state for passive push-to-talk recording.
- In push-to-talk mode:
  - show only the live level indicator while the key is held
  - remove `Cancel` and `OK`
  - switch to transcribing state automatically on key release
- Keep the existing interactive pill for manual toggle fallback sessions.

# Acceptance Criteria

- Push-to-talk recordings show a passive indicator only.
- Manual fallback recordings still expose explicit stop/cancel controls.
