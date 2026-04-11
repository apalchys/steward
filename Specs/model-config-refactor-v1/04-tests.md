---
name: Provider Catalog Refactor Tests
status: done
---

# Summary

Cover provider-first config behavior with focused regression tests.

# Scope

- Add catalog tests for derived entries, defaults, fallback, and validation.
- Keep settings migration and round-trip coverage green.
- Keep router and app-state behavior unchanged under selected feature models.

# Acceptance Criteria

- Catalog tests cover provider-first config derivation.
- Validation tests catch duplicate model IDs, invalid defaults, and duplicate defaults.
- Existing settings and router tests continue passing.
- Test suite stays green after refactor.
