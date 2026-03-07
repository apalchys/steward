# Guidelines

## Project Structure & Module Organization

- Source code lives in `Sources/Steward` (SwiftUI/Cocoa app entry in `Steward.swift`).
- Build output goes to `.build/` (managed by SwiftPM).
- `Makefile` provides shorthand developer commands that delegate to the scripts in `scripts/`.
- App bundle is assembled into `Steward.app/` by `make build`.
- Assets and icons: `Assets/`, `AppIcon.icns`.
- Top-level docs and config: `README.md`, `BUILD_INSTRUCTIONS.md`, `Package.swift`, `Info.plist`.

## Build, Test, and Development Commands

- `make build` — Release build via SwiftPM and creates `Steward.app` (codesigned locally).
- `swift build -c release` — Compile without bundling (binary in `.build/release/Steward`).
- `make fmt` — Format Swift sources with the repo's `swift-format` rules.
- `make icon` — Regenerate `AppIcon.icns` from `Assets/icon.png`.
- `open Steward.app` — Launch the bundled app.
- `open Steward.app/Contents/MacOS/Steward` — Run from Terminal.
- After first run, grant Accessibility permissions in System Settings for text capture.

## Coding Style & Naming Conventions

- Language: Swift 5.7+, macOS 13+. Prefer SwiftUI for UI and idiomatic Cocoa/AppKit usage where needed.
- Indentation: 4 spaces; line length ~120 chars.
- Naming: `UpperCamelCase` for types, `lowerCamelCase` for vars/functions/properties/constants.
- Prefer `guard`-first control flow and keep nesting shallow.
- File layout: one primary type per file; group related views/utilities near usage under `Sources/Steward`.
- In SwiftUI views, keep chained modifiers on separate lines when they stack up.
- Add comments only when behavior is non-obvious, platform-specific, or permission-related.
- Prefer type-scoped helpers and constants over new globals when practical.
- Nest request/response helper types inside the client or owner that uses them.
- Format Swift code with `swift format` using the repo's `.swift-format` config.

## Testing Guidelines

- No test target currently. If adding tests, use XCTest:
  - Create `Tests/StewardTests` and mirror module structure.
  - Name tests `ThingTests.swift`, methods `test...`.
  - Run with `swift test` and keep fast, deterministic tests.

## Commit & Pull Request Guidelines

- Follow Conventional Commits seen in history: `feat: ...`, `fix: ...`, `docs: ...`, `chore: ...`, `refactor: ...`, `test: ...`, `ci: ...`
- Scope PRs narrowly; describe what/why, include before/after notes or screenshots when UI changes.
- Link related issues; note any migration or permission changes (e.g., Accessibility prompts).
- Pass build locally and smoke-test hotkey flow before requesting review.

## Security & Configuration Tips

- The app requires an OpenAI API key and a Gemini API key; it's stored locally via app preferences/UserDefaults and only used for API calls.
- Do not hardcode keys. Users should set keys via Preferences.
- Note: App needs macOS Accessibility permission to read/replace selected text and Screen Recording permission to extract text from the screen.
