# Rewrite

A macOS application that runs in the background and fixes grammar errors in selected text using OpenAI's Responses API.

<img width="234" alt="image" src="https://github.com/user-attachments/assets/621e8498-a324-4397-ba46-504dd5dbe2f0" />


## Features

- Runs as a background application with menu bar icon
- Activated with hotkey (Command+Shift+F)
- Automatically captures selected text from any application
- Fixes grammar using OpenAI's GPT-5.4
- Uses OpenAI's Responses API for grammar corrections
- Stores your API key locally in app preferences
- Replaces original text with corrected version
- Preserves clipboard contents

## Building

See BUILD_INSTRUCTIONS.md

## Running the Application

1. After building, run the application
2. The app will appear in your menu bar with a pencil icon
3. The first time you use it, you'll need to grant accessibility permissions:
   - Go to System Preferences > Security & Privacy > Privacy > Accessibility
   - Add and enable the Rewrite application
4. Set up your OpenAI API key:
   - Click on the app icon in the menu bar
   - Select "Preferences..." (or press Command+,)
   - Enter your OpenAI API key in the settings window

## Usage

1. Select text in any application
2. Press Command+Shift+F
3. Wait a moment while the text is processed
4. The selected text will be replaced with the grammar-corrected version

## Requirements

- macOS 13.0 or later
- OpenAI API key

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) - For global hotkey registration

## Troubleshooting

If the hotkey doesn't work:
1. Ensure the application has accessibility permissions
2. Check if Command+Shift+F is already assigned to another application
3. Try restarting the application

## License

MIT
