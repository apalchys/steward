# Guidelines

## Project Structure & Module Organization

- Source code lives in `Sources/Steward` (app target) and `Sources/StewardCore` (provider clients + shared prompt helpers).
- App entry point is `Sources/Steward/Steward.swift`.
- App state / lifecycle coordination is in `Sources/Steward/AppShell.swift` (`AppState`).
- Build output goes to `.build/` (SwiftPM managed).
- App bundle is assembled into `Steward.app/` by `make build` (`scripts/build.sh`).
- Assets and icons: `Assets/`, `AppIcon.icns`.
- Top-level docs and config: `README.md`, `BUILD_INSTRUCTIONS.md`, `Package.swift`, `Info.plist`.

## Architecture

- Style: modular monolith with two SwiftPM targets (`Steward`, `StewardCore`).
- App shell:
  - SwiftUI scenes in `Steward.swift` (`MenuBarExtra`, `Window("History")`, `Settings`).
  - Runtime controller in `AppShell.swift` (`AppState`) owns hotkeys, status state, startup checks, provider checks, and clipboard monitor lifecycle.
- Feature coordination:
  - `GrammarCoordinator`
  - `ScreenOCRCoordinator`
- UI:
  - `SettingsView` (tabs: Grammar, Screenshot, About)
  - `ClipboardHistoryView`
- Platform services:
  - text selection/replacement and clipboard writes (`SystemTextInteractionService`)
  - screen capture (`SystemScreenCaptureService`)
  - area-selection overlay (`ScreenSelectionOverlayController`)
- LLM layer:
  - Contracts in `LLMModels.swift` (`LLMProviderID`, `LLMTask`, `LLMRequest`, `LLMResult`).
  - `LLMRequest` includes explicit `providerID`; there is no dynamic fallback routing.
  - Router (`LLMRouter`) validates provider registration/config and dispatches to provider adapters.
  - Provider adapters: OpenAI and Gemini (both wired for grammar + OCR tasks).
- Settings/config:
  - `LLMSettings` stores provider profiles and per-feature provider selection (`grammarProviderID`, `screenshotProviderID`).
  - Secrets (API keys) are stored via Valet (`LLMSecretsStoring` / `ValetLLMSecretsStore`).
  - Non-secrets (model IDs, selected providers, custom instructions) are stored via typed `Defaults` keys.
  - `migrateLegacySettingsIfNeeded()` is intentionally a no-op in current iteration.
- Dependency direction:
  - `AppState -> Coordinators -> LLMRouter/PlatformServices -> StewardCore clients`.
  - SwiftUI scenes/views consume `AppState` and stores; feature code must not call provider clients directly.

## Build, Test, and Development Commands

- `make build` — Release build and app bundle assembly (`Steward.app`).
- `swift build -c release` — Compile release binary only.
- `make test` — Run unit tests (`swift test`).
- `make fmt` — Format Swift sources using repo `.swift-format` config.
- `make icon` — Regenerate `AppIcon.icns` from `Assets/icon.png`.
- `open Steward.app` — Launch bundled app.
- `open Steward.app/Contents/MacOS/Steward` — Launch binary from Terminal.

## Coding Style & Naming Conventions

- Language: Swift 6.0+, macOS 15+.
- Prefer SwiftUI for UI and AppKit/Cocoa where platform APIs are required.
- Indentation: 4 spaces; line length target ~120 chars.
- Naming: `UpperCamelCase` for types, `lowerCamelCase` for members.
- Prefer `guard`-first control flow and shallow nesting.
- File layout: one primary type per file where practical.
- In SwiftUI views, keep chained modifiers on separate lines when they stack.
- Add comments only for non-obvious behavior (platform/permission nuances).
- Prefer type-scoped helpers/constants over new globals.
- Format with `swift format` (`make fmt`).

## Testing Guidelines

- Add/update tests with code changes.
- Keep tests isolated, fast, and deterministic.
- Use XCTest under `Tests/StewardTests`.
- Mirror source module areas in test naming (`ThingTests.swift`, `test...`).
- Run `make test` (or `swift test`) and keep suite green before finishing.

## Commit & Pull Request Guidelines

- Follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `ci:`).
- Keep PRs scoped and explain what/why.
- Include screenshots or before/after notes for UI changes.
- Note permission-impacting changes (Accessibility, Screen Recording, etc.).
- Pass local build and tests before review.

## Security & Configuration Tips

- Supported providers: OpenAI and Gemini.
- Do not hardcode API keys.
- API keys are stored in Keychain via Valet.
- Non-secret settings are stored locally via Defaults (`UserDefaults`).
- Clipboard history is stored locally in Application Support (`Steward/clipboard-history.jsonl`).
- App requires Accessibility permission for text capture/replacement.
- App requires Screen Recording permission for OCR capture.
