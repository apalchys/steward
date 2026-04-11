---
name: Pane Regrouping And Content Migration
status: done
---

# Summary

Regroup existing settings into clearer panes without changing stored data or app behavior.

# Scope

- Keep launch-at-login in General.
- Move provider API keys and curated model summaries into dedicated Providers pane.
- Keep per-feature model selection and custom instructions in Refine, Capture, and Dictate.
- Keep voice hotkey recorder in Dictate.
- Keep clipboard enablement, retention, storage path, and clear action in Clipboard.
- Add app identity and version/build metadata to About.

# Acceptance Criteria

- General no longer contains provider cards.
- Providers pane is sole place for API key entry.
- Refine, Capture, Dictate, Clipboard, and About expose the same underlying settings as before.
