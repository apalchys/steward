# Building Steward app

1. Install Xcode

2. Build the app

```bash
   make build
```

3. Copy `Steward.app` to Applications

## Running the Application

1. The first time you run the app, it will appear in your menu bar with a pencil icon
2. You'll need to grant accessibility permissions:
   - Go to System Preferences > Security & Privacy > Privacy > Accessibility
   - Add and enable the Steward application
3. If you want to use voice dictation, also grant Microphone permission:
   - Go to System Settings > Privacy & Security > Microphone
   - Add and enable the Steward application
4. If you want to use screen OCR, also grant Screen Recording permission:
   - Go to System Settings > Privacy & Security > Screen Recording
   - Add and enable the Steward application
5. Set up your API keys:
   - Click on the app icon in the menu bar
   - Select "Preferences..."
   - Enter your OpenAI API key in the Grammar tab
   - Enter your Gemini API key in the Screenshot tab
   - In the Voice tab, choose Gemini or OpenAI, reuse the matching API key, and optionally set a voice-specific model ID
   - Enter an optional model ID in each tab if you want to override the default
   - Clipboard history is optional and can be enabled in the History tab
   - Leaving model IDs empty falls back to `gpt-5.4` for OpenAI and `gemini-3.1-flash-lite-preview` for Gemini
6. To fix grammar, select text in any application and press `Command+Shift+F`
7. To start voice dictation, press `Command+Shift+D`, speak, then press `Command+Shift+D` again or click `OK`
8. To extract screen text, press `Command+Shift+R`, drag to select an area, and wait for the Markdown text to land in your clipboard
