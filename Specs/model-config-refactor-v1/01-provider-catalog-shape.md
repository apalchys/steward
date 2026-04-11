---
name: Provider Catalog Shape
status: done
---

# Summary

Replace flat model list with provider-first model config.

# Scope

- Add provider catalog types for provider-scoped model definitions.
- Store model capabilities and per-capability default flags in code.
- Derive existing flat catalog entries from provider config.
- Keep persisted feature model selections unchanged.

# Acceptance Criteria

- Model config is declared per provider in one source file.
- Each model declares supported capabilities and default capabilities.
- Existing consumers can still read flat catalog entries without UI changes.
- Invalid config can be detected by validation logic.
