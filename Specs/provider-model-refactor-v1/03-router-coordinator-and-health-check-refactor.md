---
name: Router Coordinator And Health Check Refactor
status: done
---

# Summary

Update request routing and feature coordinators so execution and health checks use the selected feature model directly.

# Scope

- Change LLM requests to carry an explicit selected model.
- Update the router to build provider configuration from provider API keys plus the selected model.
- Update Refine, Capture, and Dictate coordinators to read feature selections from settings.
- Update app-state health checks to validate the selected feature model instead of provider defaults.

# Acceptance Criteria

- Refine, Capture, and Dictate requests all use the model selected on their respective tabs.
- Health checks report against the selected model and still distinguish invalid API keys from invalid models.
- Missing feature model selection surfaces as a configuration error instead of falling through to provider clients.
