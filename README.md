# Steward

Steward is a macOS menu bar app for two quick actions:
- fix selected text grammar
- convert a screenshot selection into Markdown

It supports OpenAI and Gemini, with provider choice configured per feature.

## Features

- Menu bar app (`LSUIElement`) built with SwiftUI `MenuBarExtra`
- Global hotkeys:
  - Grammar check: `Command+Shift+F`
  - Screenshot to Markdown: `Command+Shift+R`
- Three-tab preferences UI:
  - Grammar
  - Screenshot
  - About
- Per-feature provider selection (OpenAI or Gemini) with per-provider API key/model
- Per-feature custom instructions:
  - grammar instructions
  - screenshot instructions
- Provider health checks from the menu (click Grammar/OCR status rows to re-check)
- Clipboard history window with search, detail view, delete, and clear-all
- Status icon/title states for ready, processing, and error

## Requirements

- macOS 15.0+
- Xcode command line tools / Swift 6.0 toolchain
- At least one provider API key:
  - OpenAI: [https://platform.openai.com/](https://platform.openai.com/)
  - Gemini: [https://aistudio.google.com/](https://aistudio.google.com/)

## Build and Run

See [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for a quick build flow.

Common commands:

```bash
make fmt      # format Sources/* with swift-format
make test     # run tests
make build    # build release and assemble Steward.app
make icon     # regenerate AppIcon.icns from Assets/icon.png
```

Run:

```bash
open Steward.app
```

## First Launch Setup

1. Launch `Steward.app`.
2. Grant Accessibility permission (required for selected-text read/replace).
3. Grant Screen Recording permission (required for screenshot OCR).
4. Open `Preferences...` from the menu bar app.
5. Configure each feature tab:
   - pick provider (OpenAI or Gemini)
   - set API key
   - optionally set model (empty uses provider default)
   - optionally set custom instructions

## Usage

Grammar:
1. Select text in any app.
2. Press `Command+Shift+F`.
3. Steward replaces the selected text with corrected output.

Screenshot to Markdown:
1. Press `Command+Shift+R`.
2. Drag to select a region.
3. Steward copies extracted Markdown to clipboard.

Clipboard history:
1. Open menu bar app.
2. Click `History`.
3. Search/view/delete records as needed.

## Storage and Privacy

- API keys are stored in macOS Keychain via `Square/Valet`.
- Non-secret settings (model IDs, selected providers, custom instructions) are stored with `Defaults` (`UserDefaults`).
- Clipboard history is stored locally as JSONL at `~/Library/Application Support/Steward/clipboard-history.jsonl`.
- Data is sent only to the provider you configure for the feature being run.

## Dependencies

- [HotKey](https://github.com/soffes/HotKey)
- [Defaults](https://github.com/sindresorhus/Defaults)
- [Valet](https://github.com/square/Valet)

## License

MIT
