---
name: Settings Shell And Sidebar
status: done
---

# Summary

Replace tab-based settings with native macOS split-view shell and sidebar navigation.

# Scope

- Rebuild settings window around `NavigationSplitView`.
- Add fixed pane order: General, Providers, Refine, Capture, Dictate, Clipboard, About.
- Set wider settings window sizing and cap main content width for readability.
- Use native sidebar list styling, system materials, large pane titles, and standard spacing.

# Acceptance Criteria

- Settings opens as sidebar-driven window instead of toolbar tabs.
- Sidebar selection switches panes without changing persisted settings behavior.
- Window layout remains readable across normal resize ranges on macOS 15.
