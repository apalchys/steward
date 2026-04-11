# Guidelines

## Communication

- Use telegram-style communication. Be ultra concise: cut all unnecessary words. Omit grammar, punctuation, articles, conjunctions, filler, hedges, greetings etc. No emojis, no apologies, no explanations unless required. Strip everything nonessential to maximize information per token.

## Project Structure & Module Organization

- Source code lives in `Sources/Steward` (app target) and `Sources/StewardCore` (provider clients + shared prompt helpers).
- App entry point is `Sources/Steward/Steward.swift`.
- App state / lifecycle coordination is in `Sources/Steward/AppShell.swift` (`AppState`).
- Build output goes to `.build/` (SwiftPM managed).
- App bundle is assembled into `Steward.app/` by `make build`.
- Assets and icons: `Assets/`, `AppIcon.icns`.
- Top-level docs and config: `README.md`, `BUILD_INSTRUCTIONS.md`, `Package.swift`, `Info.plist`.

## Architecture

- Style: modular monolith with two SwiftPM targets — an app target and a core library for provider clients and shared helpers.
- Layers (top to bottom):
  - SwiftUI scenes — menu bar extra, windows, settings.
  - App state — a single `@MainActor ObservableObject` that owns lifecycle, hotkeys, status, and wires coordinators to services.
  - Feature coordinators — one per feature. Each orchestrates a router, text interaction, and any additional services needed for its workflow.
  - Router — validates provider registration/configuration and dispatches requests to the correct provider adapter. Requests carry an explicit provider ID; there is no dynamic fallback.
  - Platform services — protocol-backed wrappers for text selection/replacement, clipboard, screen capture, and selection overlay.
  - Core clients — HTTP clients for each LLM provider, living in the core library target.
- Dependency direction is strictly top-down: scenes → app state → coordinators → router/services → core clients. Feature code must never call provider clients directly.

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

- Keep tests isolated, fast, and deterministic.
- Use XCTest under `Tests/StewardTests`.
- Mirror source module areas in test naming (`ThingTests.swift`, `test...`).
- Run `make test` (or `swift test`) and keep suite green before finishing.

## Commit & Pull Request Guidelines

- Follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `ci:`).
- Keep PRs scoped and explain what/why.
- Note permission-impacting changes (Accessibility, Screen Recording, etc.).

## Security & Configuration Tips

- Supported providers: OpenAI and Gemini.
- All settings, including API keys, are stored locally via Defaults (`UserDefaults`).
- Clipboard history is stored locally in Application Support (`Steward/clipboard-history.jsonl`).
- App requires Accessibility permission for text capture/replacement.
- App requires Screen Recording permission for OCR capture.

## Specs

Use the "Specs" folder to store the project specifications. Break down the specifications into small, deliverable tasks and save them as Markdown files. The naming convention for the specifications is "{feature-name}/{number}-{task-name}.md". Example: "voice-dictation-v1/01-voice-settings-model.md".

Each task markdown file should have:

1. Frontmatter fields:
    - name: The name of the task.
    - status: The status of the task. Can be "todo", "done".
2. Summary section: A brief description of the task.
3. Scope section: A detailed description of the task.
4. Acceptance Criteria section: A list of criteria that must be met for the task to be considered complete.

Mark the task as "done" when it is fully implemented and tested.

## Development Principles

1. Follow Apple Human Interface Guidelines (https://developer.apple.com/design/human-interface-guidelines). When in doubt, match first-party macOS apps.
2. Define all dependencies as protocols, accept them via `init` with production defaults. No singletons, no global state.
3. Use `async/await`, `Task`, `@MainActor` for concurrency. Never `DispatchQueue.main.async` or `Thread.sleep`.
4. Views only observe state and fire actions. No I/O, no service calls, no business logic in SwiftUI views.
5. Services and coordinators `throw` typed errors. App state catches at the boundary, updates status, and logs.
6. Secrets (API keys) go in `UserDefaults`. Non-sensitive preferences go in `UserDefaults`. Never hard-code secrets in source.
7. Guard platform permissions (Accessibility, Screen Recording) at workflow start, before any UI or side effects.
8. Menu-bar apps use `.accessory` activation policy. Overlay windows stay above apps but below system security UI.
9. Log with `os.Logger` (consistent subsystem + per-module category), not `print`.
10. Append-only persistence for local stores. Skip malformed entries on load. Atomic rewrites only for deletions.
