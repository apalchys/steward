---
name: Settings Model And Migration
status: done
---

# Summary

Refactor persisted settings so providers store API keys only and each feature stores its own selected model.

# Scope

- Replace provider-level `apiKey + modelID` storage with provider API-key storage only.
- Introduce feature-scoped settings for Refine, Capture, and Dictate.
- Persist per-feature model selections as provider/model pairs.
- Migrate legacy refine, screen, and voice model settings into the new structure.
- Clear legacy model keys after saving in the new schema.

# Acceptance Criteria

- Provider settings persist API keys without storing provider-level model IDs.
- Refine, Capture, and Dictate each persist their own selected model.
- Legacy saved settings load into the new structure with fallback when a legacy model is no longer in the curated catalog.
- When no compatible enabled model exists, the feature remains unconfigured instead of keeping a stale invalid selection.
