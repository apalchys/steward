# PLAN_GPT

## Mission

- Bring Steward from working prototype quality to solid modern macOS quality.
- Prioritize reliability, privacy, accessibility, and maintainability before adding any new end-user features.
- Prefer the smallest correct change that removes real risk.
- Follow macOS conventions and the repo rules in AGENTS.md.
- Avoid framework churn, speculative abstractions, and cleanup that does not improve behavior.

## Ground Rules

- Keep the app as a menu bar utility on macOS 15+ with Swift 6.
- Keep SwiftUI at the UI layer and AppKit only at platform boundaries.
- Use async and await, Task, and actor or MainActor isolation instead of ad hoc queue hopping.
- Do not introduce a DI framework, state framework, or generic retry framework.
- Do not migrate to Observation or @Observable unless a concrete problem requires it.
- Do not add an Apply button to Settings. Keep live-save behavior and make it disciplined.
- Do not force an AX-only text workflow. Use Accessibility first with a fallback path.
- Do not remove all timing delays blindly. Remove unjustified sleeps, but keep the minimal bounded delay where macOS rendering requires it.

## Resolved Decisions

- Selected text workflow should be AX-first with synthetic copy and paste fallback.
- Clipboard restore must never overwrite user clipboard changes that happened after Steward started its operation.
- Settings should stay live-edit, but provider checks must be debounced and cancellable.
- AppKit and pasteboard driven services should be MainActor isolated unless there is a clear reason not to be.
- Stateless services should stay simple. Do not convert everything into actors.
- Move object graph assembly out of AppState, but keep the solution lightweight and explicit.
- Clipboard history should be off by default and clearly explained before it starts collecting data.
- Menu bar actions must be clickable and accessible, not hotkey-only.
- Provider health should return small typed diagnostics, not only Bool.
- baseURL support should be removed unless custom endpoints are a real near-term requirement.

## Recommended Scope Decision for baseURL

- Default recommendation is to remove custom baseURL support now.
- Rationale: the setting is dead today, there is no UI for it, and keeping hidden configuration increases complexity.
- If there is an explicit product requirement for local or proxy endpoints, keep the field and wire it end to end in the same change.
- Do not leave baseURL half-supported.

## Priority Order

1. Privacy and trust issues
2. Core text interaction reliability
3. Settings and health check discipline
4. Accessibility and menu usability
5. Targeted concurrency and lifecycle cleanup
6. Architecture cleanup that makes testing easier
7. Secondary polish and resilience

## Phase 0 Quick Wins

- Fix documentation drift so BUILD_INSTRUCTIONS.md matches the actual Keychain storage behavior.
- Replace static menu rows for primary actions with real buttons.
- Add an accessible title or accessibility label to the MenuBarExtra icon.
- Audit and remove remaining DispatchQueue.main.async usage that violates repo concurrency rules, including the one noted in ClipboardHistoryView.swift.
- Replace callback wrapping around SCShareableContent with the native async API available on the deployment target.

## Phase 1 Privacy and Trust

- Add a user-visible clipboard history toggle in Settings.
- Default clipboard history to off for new installs.
- Only start ClipboardMonitor when the feature is enabled.
- Add clear explanation text in Settings describing what is stored, where it is stored, and that it stays local.
- Add a clear history action.
- Keep storage append-only, but stop recording immediately when the feature is disabled.
- Add a simple bounded retention policy that is easy to reason about.
- Recommended KISS option is max item count plus clear history, unless the product explicitly needs time-based retention.
- Update README and any onboarding copy so clipboard history behavior is transparent.

## Phase 2 Selected Text Workflow

- Introduce a text interaction strategy that first attempts Accessibility APIs on the focused element.
- Read selected text with AX when supported.
- Replace selected text with AX when supported.
- Fall back to synthetic Cmd-C and Cmd-V only when AX read or write is unavailable or unsupported by the target app.
- Keep the fallback isolated in one place and document why it exists.
- Replace fixed 200 ms pasteboard waits with bounded polling on pasteboard change count and timeout.
- Replace delayed clipboard restore with structured concurrency.
- Restore the clipboard only if the pasteboard still contains Steward temporary content.
- If the user changed the clipboard after Steward started, do not overwrite it.
- Keep permission checks explicit and fail with typed errors when Accessibility is unavailable.
- Make the text interaction service MainActor isolated.

## Phase 3 OCR Flow and Overlay Handshake

- Keep ScreenCaptureKit as the capture mechanism.
- Replace raw sleep-based sequencing with an explicit overlay dismissal flow.
- The overlay controller should expose a clear async boundary for selection start, cancel, and completion.
- After dismissing the overlay, wait the smallest justified delay before capture so the overlay is not included in the screenshot.
- Document that this delay exists because window removal is not instant at the compositor level.
- Do not build a complicated event pipeline to avoid a delay that macOS still requires in practice.
- Add visible instruction text to the overlay.
- Add a visible Escape to cancel hint.
- Add accessibility labels for overlay content.

## Phase 4 Settings and Provider Health

- Keep settings live-saving.
- Debounce health checks triggered by settings edits.
- Cancel in-flight health checks when newer edits arrive.
- Avoid firing provider checks on every keystroke in secure or text fields.
- Use one owned task per provider status check path so AppState can cancel stale work.
- Surface clear status states such as idle, checking, configured, not configured, invalid credentials, network issue, endpoint issue, model issue, and unknown error.
- Keep the diagnostic model small and user-facing. Do not build a large observability layer.
- If baseURL is kept, expose it in Settings and pass it all the way into OpenAIClient and GeminiClient construction.
- If baseURL is removed, delete it from settings models, storage, tests, and docs in the same pass.
- Add lightweight retry with backoff only for transient failures such as timeout, 429, or select 5xx responses.
- Do not retry invalid credentials, unsupported models, or malformed configuration.

## Phase 5 AppState, Lifecycle, and Dependency Assembly

- Move concrete service creation out of AppState and into the app root or a small bootstrap builder.
- Inject protocol-backed dependencies into AppState with production defaults assembled at the top level.
- Keep the dependency graph explicit and small.
- Do not introduce service locators, singletons, or a third-party DI container.
- Keep AppState responsible for orchestration, user-visible status, and task ownership.
- Ensure startup is idempotent.
- If startup currently needs a guard because of SwiftUI menu bar lifecycle quirks, use a simple hasStarted guard instead of init side effects spread across multiple places.

## Phase 6 Isolation and Sendable Cleanup

- Remove @unchecked Sendable where it is masking AppKit or main-thread-only access.
- Mark ClipboardMonitor as MainActor.
- Mark text interaction services that touch NSPasteboard or AppKit APIs as MainActor.
- Convert trivially stateless services to structs if that removes Sendable noise cleanly.
- Reevaluate LLMRouter isolation based on its actual dependencies instead of forcing one pattern.
- Keep ClipboardHistoryStore queue-isolated if that remains the simplest correct design.
- Convert ClipboardHistoryStore to an actor only if it materially simplifies correctness and tests.
- Prefer proving safety with actor or MainActor isolation over asserting it with unchecked annotations.

## Phase 7 Menu Bar and Interaction Polish

- Ensure the menu exposes both primary actions as buttons.
- Keep hotkeys, but do not make them the only way to discover features.
- Show provider and permission status in a way that is concise and actionable.
- Add user feedback if global hotkey registration fails because another app already owns the shortcut.
- Review the Settings window opening path and replace undocumented behavior if a cleaner public option is viable on the target OS.
- If a fully public replacement is not available, isolate the workaround and document the tradeoff.

## Phase 8 Secondary Cleanup

- Verify model defaults and other configuration values in documentation so they do not drift.
- Review provider request error mapping so user-visible messages stay specific but not noisy.
- Keep local persistence behavior append-only and robust against malformed rows.
- Avoid adding new feature scope until the above work is complete and tested.

## What Not To Do

- Do not migrate the whole app to @Observable as part of this effort.
- Do not introduce a broad architecture rewrite.
- Do not replace every queue with an actor just for style consistency.
- Do not add keyboard-only region selection unless there is a concrete accessibility requirement beyond current app scope.
- Do not add a complex caching, telemetry, or analytics system.
- Do not add multi-provider fallback routing. The explicit provider model is correct.
- Do not keep hidden or dead settings.

## Implementation Sequence

- Start with docs, menu buttons, accessibility label, async ScreenCaptureKit API, and obvious DispatchQueue cleanup.
- Add clipboard history opt-in and clear history before any deeper refactor so privacy risk is reduced immediately.
- Rework selected text handling next because it is the most fragile core feature.
- Fix settings debounce and typed health diagnostics after text interaction is stable.
- Then move composition out of AppState and clean up isolation annotations.
- Finish with overlay polish, hotkey failure UX, and retry behavior.

## Test Plan

- Add tests for clipboard history opt-in behavior and disabled-by-default startup.
- Add tests for text interaction fallback selection logic.
- Add tests for pasteboard polling timeout and restore safety when the user changes the clipboard mid-flow.
- Add tests for permission-denied errors in AX and screen capture paths.
- Add tests for health check debounce and stale task cancellation.
- Add tests for startup idempotence.
- Add tests for typed provider health mapping from common error cases.
- Add tests covering baseURL removal or baseURL wiring, depending on the chosen scope decision.
- Add a focused integration-style test for the grammar flow through AppState using fakes.
- Add a focused integration-style test for the OCR flow through AppState using fakes.
- Keep make test green throughout the sequence instead of batching test fixes at the end.

## Acceptance Criteria

- Clipboard history does not collect data until the user explicitly enables it.
- Selected text read and replace no longer depend only on fragile synthetic copy and paste.
- Clipboard restoration no longer clobbers user clipboard updates.
- Settings edits do not trigger provider checks on every keystroke.
- Provider status shows actionable reasons instead of a generic pass or fail.
- Primary app actions are available from the menu and accessible to VoiceOver users.
- AppState no longer constructs the full object graph internally.
- Main-thread-only services are isolated correctly without broad unchecked Sendable escape hatches.
- The OCR overlay shows clear instructions and does not appear in captured images.
- BUILD_INSTRUCTIONS.md and README.md match real storage and configuration behavior.

## Final Guidance for the Implementation Agent

- Prefer one coherent pass per phase over touching every subsystem at once.
- When a decision has both a clean architectural answer and a pragmatic macOS caveat, choose the pragmatic version and document the reason.
- If a cleanup does not improve correctness, UX, privacy, or testability, skip it.
- Keep the implementation obviously simpler after each phase, not just more abstract.
