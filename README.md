# Steward

<img width="120" height="120" alt="Steward app icon" src="https://github.com/user-attachments/assets/27fcee3a-b017-4665-8048-71de5360ba9d" />

Steward is a macOS menu bar app for four text workflows:

- `Refine` rewrites selected text in place.
- `Capture` extracts Markdown from a selected screen region.
- `Dictate` records speech and inserts the cleaned transcript into the focused app.
- `Clipboard` keeps a searchable local history of copied text.

Steward uses curated OpenAI and Gemini model lists. Providers are unlocked in `Preferences > Providers`, and each feature picks its own compatible model in `Refine`, `Capture`, or `Dictate`.

<img height="250" alt="Steward settings" src="https://github.com/user-attachments/assets/06395f67-1ad1-4b72-88df-ed6e7faa3e23" />
<img height="250" alt="Steward menu bar UI" src="https://github.com/user-attachments/assets/de00d44b-bd28-4fcf-9b9b-2698fbb376cd" />

## Features

### Refine

1. Select text in any app.
2. Press `Command+Shift+F`.
3. Steward replaces the selection with refined text from the configured model.

### Capture

1. Press `Command+Shift+R`.
2. Drag to select a screen region.
3. Steward extracts Markdown and copies it to the clipboard.

### Dictate

1. Hold the Dictate shortcut to record. Default: `Control+Shift+Space`.
2. Quick double press the same shortcut to latch Dictate without holding.
3. While latched, press the shortcut once more to stop and transcribe.
4. If Dictate is started from the menu bar item, Steward uses the manual toggle flow with `Cancel` and `OK`.
5. Steward can bias recognition toward up to 5 preferred languages, or auto-detect when none are selected.
6. Optional translate mode inserts only the translated output in the configured target language.

Dictate preserves the spoken language by default, applies punctuation and paragraph formatting, and falls back to the clipboard if direct insertion fails.

### Clipboard History

1. Enable recording in `Preferences > Clipboard`.
2. Open `Clipboard History` from the menu bar.
3. Search, review, or delete stored entries.

## Setup

Requirements:

- macOS 15.0+
- At least one provider API key:
  - OpenAI: [platform.openai.com](https://platform.openai.com/)
  - Gemini: [aistudio.google.com](https://aistudio.google.com/)

First launch:

1. Open `Steward.app`.
2. Grant Accessibility permission for text selection and replacement.
3. Grant Microphone permission for Dictate.
4. Grant Screen Recording permission for Capture.
5. Open `Preferences > Providers` and add API keys for the providers you want.
6. Open `Preferences > Refine`, `Capture`, and `Dictate` to choose models, shortcuts, language preferences, and optional custom instructions.

## Build

See [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for full build details.

```bash
make build
make test
make fmt
open Steward.app
```

## Privacy

- API keys and settings are stored locally in `UserDefaults`.
- Clipboard history is stored locally at `~/Library/Application Support/Steward/clipboard-history.jsonl`.
- Clipboard history is enabled by default until you disable it.
- Requests are sent only to the provider and model selected for each feature.
- Dictate sends recorded audio only to the configured Dictate provider.

## Dependencies

- [HotKey](https://github.com/soffes/HotKey)
- [Defaults](https://github.com/sindresorhus/Defaults)

## License

MIT
