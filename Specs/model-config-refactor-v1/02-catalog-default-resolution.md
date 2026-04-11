---
name: Catalog Default Resolution
status: done
---

# Summary

Make model fallback and default resolution explicit.

# Scope

- Add helper to resolve provider defaults per capability.
- Preserve valid saved selections.
- Prefer preferred-provider default, then preferred-provider compatible model.
- Fall back across enabled providers by catalog order.

# Acceptance Criteria

- Default resolution no longer depends on incidental flat list order.
- Invalid selections fall back deterministically.
- Cross-provider fallback respects provider config order.
- No compatible enabled model returns no selection.
