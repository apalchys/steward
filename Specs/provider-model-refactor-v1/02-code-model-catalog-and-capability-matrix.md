---
name: Code Model Catalog And Capability Matrix
status: done
---

# Summary

Add a code-only curated model catalog that declares provider, raw model ID, and feature capabilities in one place.

# Scope

- Introduce a central curated model catalog source file.
- Define the feature capability matrix for refine, screen text, and voice per model entry.
- Add helpers to filter models by feature and enabled providers.
- Add fallback and sanitization logic that uses catalog order as the priority mechanism.

# Acceptance Criteria

- The curated list is declared in one source file and is easy to extend.
- Each model entry explicitly states which features it supports.
- Feature pickers only expose models that are both compatible and unlocked.
- Selection fallback prefers the same provider when possible, then falls back by catalog order.
