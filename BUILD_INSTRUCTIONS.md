# Building Rewrite app

1. Install Xcode

2. Build the app

```bash
   sh build_app.sh
```

3. Copy to `Rewrite.app` to Applications

## Running the Application

1. The first time you run the app, it will appear in your menu bar with a pencil icon
2. You'll need to grant accessibility permissions:
   - Go to System Preferences > Security & Privacy > Privacy > Accessibility
   - Add and enable the Rewrite application
3. If you want to use screen OCR, also grant Screen Recording permission:
   - Go to System Settings > Privacy & Security > Screen Recording
   - Add and enable the Rewrite application
4. Set up your API keys:
   - Click on the app icon in the menu bar
   - Select "Preferences..." (or press Command+,)
   - Enter your OpenAI API key for grammar correction
   - Enter your Gemini API key for screen text extraction
5. To fix grammar, select text in any application and press `Command+Shift+F`
6. To extract screen text, press `Command+Shift+R`, drag to select an area, and wait for the Markdown text to land in your clipboard

## API Key Information

The application requires an OpenAI API key for grammar correction and a Gemini API key for screen OCR. Your API keys:
- Are stored locally in UserDefaults
- Are only sent to the corresponding model provider when that feature runs
- Can be updated at any time through the Preferences menu

You can obtain API keys at https://platform.openai.com/ and https://aistudio.google.com/
