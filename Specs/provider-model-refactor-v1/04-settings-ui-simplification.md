---
name: Settings UI Simplification
status: done
---

# Summary

Move provider setup to General and simplify feature tabs to model selection plus feature-specific options.

# Scope

- Add a Providers section to General for API key management.
- Show the curated provider model list and capability summary in General.
- Replace feature-level provider/API key inputs with a single compatible model picker per feature.
- Keep feature-specific custom instructions and the voice hotkey UI unchanged where applicable.
- Show setup guidance when no compatible enabled models are available.

# Acceptance Criteria

- General contains provider API key setup.
- Refine, Capture, and Dictate each expose a single model picker labeled with provider and model.
- Feature tabs no longer ask for provider selection or API keys.
- A missing compatible model is explained with a clear message pointing the user to General.
