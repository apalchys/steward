# Guidelines

## Project Structure & Module Organization

- Source code lives in `Sources/Steward` (app entry in `Steward.swift`) and `Sources/StewardCore` (API clients + shared grammar helpers).
- Build output goes to `.build/` (managed by SwiftPM).
- `Makefile` provides shorthand developer commands that delegate to the scripts in `scripts/`.
- App bundle is assembled into `Steward.app/` by `make build`.
- Assets and icons: `Assets/`, `AppIcon.icns`.
- Top-level docs and config: `README.md`, `BUILD_INSTRUCTIONS.md`, `Package.swift`, `Info.plist`.

## Architecture

- Style: modular monolith with two SwiftPM targets (`Steward`, `StewardCore`).
- App shell (`AppShell.swift`): lifecycle, menu bar, hotkeys, status, coordinator wiring.
- Feature coordinators: `GrammarCoordinator`, `ScreenOCRCoordinator`, `HistoryCoordinator`, `PreferencesCoordinator`.
- Platform services: side-effect wrappers for text selection/replacement, clipboard writes, screen capture, and selection overlay UI.
- LLM layer:
  - Contracts in `LLMModels.swift` (`LLMProviderID`, `LLMCapability`, `LLMTask`, `LLMRequest`, `LLMResult`).
  - Routing in `LLMRouter.swift` with deterministic provider resolution:
    1) feature override, 2) global default, 3) first configured capable provider.
  - Provider adapters: OpenAI, Gemini, OpenAI-compatible endpoint.
- Settings/config:
  - `LLMSettings.swift` stores provider profiles (`apiKey`, `modelID`, optional `baseURL`) plus global and per-feature overrides.
  - Legacy `openAIApiKey`/`geminiAPIKey` settings are migrated once into provider profiles.
- Dependency direction:
  - `AppShell -> Coordinators -> LLMRouter/PlatformServices -> StewardCore clients`.
  - Feature code must not call provider-specific clients directly.

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

- Plan tests while writing code and favor designs that are easy to test in isolation; keep logic decoupled from UI, globals, and system side effects when practical.
- Unit tests should be small, concise, efficient, and atomic; each test should verify one behavior and stay fast and deterministic.
- All new code should include tests. Use XCTest under `Tests/StewardTests`, mirror the source module structure, name files `ThingTests.swift` with methods `test...`, run them with `swift test`, and make sure the full test suite is green before finishing.

## Commit & Pull Request Guidelines

- Follow Conventional Commits seen in history: `feat: ...`, `fix: ...`, `docs: ...`, `chore: ...`, `refactor: ...`, `test: ...`, `ci: ...`
- Scope PRs narrowly; describe what/why, include before/after notes or screenshots when UI changes.
- Link related issues; note any migration or permission changes (e.g., Accessibility prompts).
- Pass build locally and smoke-test hotkey flow before requesting review.

## Security & Configuration Tips

- API keys and models are stored locally in UserDefaults as provider profiles and used only for outbound provider API calls.
- Supported providers currently: OpenAI, Gemini, OpenAI-compatible endpoint (custom base URL).
- Do not hardcode keys. Users should set keys via Preferences.
- Note: app needs macOS Accessibility permission to read/replace selected text and Screen Recording permission for OCR capture.
