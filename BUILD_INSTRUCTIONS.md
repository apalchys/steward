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
3. Set up your OpenAI API key:
   - Click on the app icon in the menu bar
   - Select "Preferences..." (or press Command+,)
   - Enter your OpenAI API key in the settings window
4. To use, select text in any application and press `Command+Shift+F`

## API Key Information

The application requires an OpenAI API key to function. Your API key:
- Is stored locally in UserDefaults
- Is only sent to OpenAI's Responses API to process your selected text
- Can be updated at any time through the Preferences menu

You can obtain an API key by creating an account at https://platform.openai.com/
