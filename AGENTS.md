# Guidelines

## Project Structure & Module Organization

- Source code lives in `Sources/Steward` (SwiftUI/Cocoa app entry in `Steward.swift`).
- Build output goes to `.build/` (managed by SwiftPM).
- App bundle is assembled into `Steward.app/` by `build_app.sh`.
- Assets and icons: `Assets/`, `AppIcon.icns`.
- Top-level docs and config: `README.md`, `BUILD_INSTRUCTIONS.md`, `Package.swift`, `Info.plist`.

## Build, Test, and Development Commands

- `sh build_app.sh` — Release build via SwiftPM and creates `Steward.app` (codesigned locally).
- `swift build -c release` — Compile without bundling (binary in `.build/release/Steward`).
- `open Steward.app` — Launch the bundled app.
- `open Steward.app/Contents/MacOS/Steward` — Run from Terminal.
- After first run, grant Accessibility permissions in System Settings for text capture.

## Coding Style & Naming Conventions

- Language: Swift 5.7+, macOS 13+. Prefer SwiftUI for UI and idiomatic Cocoa/AppKit usage where needed.
- Indentation: 4 spaces; line length ~120 chars.
- Naming: `UpperCamelCase` for types, `lowerCamelCase` for vars/functions, `SCREAMING_SNAKE_CASE` for constants.
- File layout: one primary type per file; group related views/utilities near usage under `Sources/Steward`.
- No linter is enforced. Keep formatting consistent with existing code. Consider `swift-format` locally if desired.

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
