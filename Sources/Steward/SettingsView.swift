import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var clipboardHistoryStore: ClipboardHistoryStore
    @State private var settings: LLMSettings
    @State private var showClearHistoryConfirmation = false

    private let settingsStore: any AppSettingsProviding
    private let onSettingsChanged: (() -> Void)?

    private var grammarProviderID: LLMProviderID {
        LLMSettings.grammarProvider
    }

    private var screenshotProviderID: LLMProviderID {
        LLMSettings.screenshotProvider
    }

    init(
        appState: AppState,
        settingsStore: any AppSettingsProviding = UserDefaultsLLMSettingsStore(),
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore(autoLoad: false),
        onSettingsChanged: (() -> Void)? = nil
    ) {
        _appState = ObservedObject(wrappedValue: appState)
        self.settingsStore = settingsStore
        self.onSettingsChanged = onSettingsChanged
        _clipboardHistoryStore = ObservedObject(wrappedValue: clipboardHistoryStore)
        _settings = State(initialValue: settingsStore.loadSettings())
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            grammarTab
                .tabItem {
                    Label("Grammar", systemImage: "text.book.closed")
                }

            screenshotTab
                .tabItem {
                    Label("Screen Text", systemImage: "photo.on.rectangle")
                }

            voiceTab
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                }

            historyTab
                .tabItem {
                    Label("Clipboard", systemImage: "clipboard")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 760, height: 520)
        .onAppear {
            settings = settingsStore.loadSettings()
            appState.refreshLaunchAtLoginStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshLaunchAtLoginStatus()
        }
        .onChange(of: settings) { _, newSettings in
            persistSettings(newSettings)
        }
        .alert("Clear clipboard history?", isPresented: $showClearHistoryConfirmation) {
            Button("Clear History", role: .destructive) {
                clipboardHistoryStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all locally stored clipboard history.")
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("General")
                    .font(.headline)

                Toggle("Launch Steward at login", isOn: launchAtLoginBinding)
                    .disabled(appState.isUpdatingLaunchAtLogin)

                Text("Steward uses macOS Login Items and follows your system-level preference.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let launchAtLoginMessage = appState.launchAtLoginMessage {
                    Text(launchAtLoginMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if appState.shouldShowOpenLoginItemsAction {
                    Button("Open Login Items Settings") {
                        appState.openLoginItemsSettings()
                    }
                }
            }
            .padding(20)
        }
    }

    private var grammarTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Grammar")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.subheadline)

                    Text(grammarProviderID.displayName)
                        .foregroundColor(.secondary)
                }

                ContinuousSecureField(
                    placeholder: "\(grammarProviderID.displayName) API Key",
                    text: profileBinding(for: grammarProviderID, keyPath: \.apiKey)
                )
                .frame(height: 22)

                TextField(
                    "Model (default: \(grammarProviderID.defaultModelID))",
                    text: profileBinding(for: grammarProviderID, keyPath: \.modelID)
                )
                .textFieldStyle(.roundedBorder)

                Text("Custom instructions for grammar check")
                    .font(.subheadline)

                TextEditor(text: $settings.grammarCustomInstructions)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .frame(minHeight: 220)

                Text("Used as additional guidance when fixing grammar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)
        }
    }

    private var screenshotTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Screenshot to Markdown")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.subheadline)

                    Text(screenshotProviderID.displayName)
                        .foregroundColor(.secondary)
                }

                ContinuousSecureField(
                    placeholder: "\(screenshotProviderID.displayName) API Key",
                    text: profileBinding(for: screenshotProviderID, keyPath: \.apiKey)
                )
                .frame(height: 22)

                TextField(
                    "Model (default: \(screenshotProviderID.defaultModelID))",
                    text: profileBinding(for: screenshotProviderID, keyPath: \.modelID)
                )
                .textFieldStyle(.roundedBorder)

                Text("Custom instructions for screenshot to markdown")
                    .font(.subheadline)

                TextEditor(text: $settings.screenshotCustomInstructions)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .frame(minHeight: 220)

                Text("Used as additional guidance when extracting text from screenshots.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)
        }
    }

    private var historyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Clipboard")
                    .font(.headline)

                Toggle("Enable clipboard history", isOn: $settings.clipboardHistory.isEnabled)

                Text("Clipboard history is stored only on this Mac and is enabled by default.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Stepper(
                        value: $settings.clipboardHistory.maxStoredRecords,
                        in: 1...ClipboardHistorySettings.maxStoredRecordsLimit,
                        step: ClipboardHistorySettings.maxStoredRecordsStep
                    ) {
                        Text("Keep up to \(settings.clipboardHistory.maxStoredRecords) entries")
                    }

                    Text("Older entries are removed automatically when the limit is reached.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disabled(!settings.clipboardHistory.isEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Storage")
                        .font(.subheadline)

                    Text(ClipboardHistoryStore.defaultHistoryFileURL().path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundColor(.secondary)
                }

                Button("Clear Stored History", role: .destructive) {
                    showClearHistoryConfirmation = true
                }
                .disabled(clipboardHistoryStore.records.isEmpty)

                Text(
                    "When disabled, Steward stops recording new clipboard entries immediately. Existing history remains until you clear it."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(20)
        }
    }

    private var voiceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Voice Dictation")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.subheadline)

                    Picker("Voice provider", selection: $settings.voice.providerID) {
                        ForEach(LLMProviderID.allCases) { providerID in
                            Text(providerID.displayName)
                                .tag(providerID)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ContinuousSecureField(
                    placeholder: "\(selectedVoiceProviderID.displayName) API Key",
                    text: profileBinding(for: selectedVoiceProviderID, keyPath: \.apiKey)
                )
                .frame(height: 22)

                TextField(
                    "Model (default: \(selectedVoiceDefaultModelID))",
                    text: voiceModelBinding(for: selectedVoiceProviderID)
                )
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcut")
                        .font(.subheadline)

                    Text("Command-Shift-D")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text("Custom instructions for voice transcription")
                    .font(.subheadline)

                TextEditor(text: $settings.voice.customInstructions)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .frame(minHeight: 220)

                Text("Dictation keeps the spoken language(s) and applies punctuation and formatting automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Version 1 is optimized for recordings up to 120 seconds.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .center, spacing: 12) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            } else if let iconURL = Bundle.main.url(forResource: "icon", withExtension: "png")
                ?? Bundle.main.resourceURL?.appendingPathComponent("icon.png"),
                let iconImage = NSImage(contentsOf: iconURL)
            {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "pencil.and.outline")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
            }

            Text("Steward")
                .font(.largeTitle)
                .bold()

            Text("Steward helps you polish writing and turn screenshot text into clean Markdown in seconds.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func profileBinding(
        for providerID: LLMProviderID,
        keyPath: WritableKeyPath<LLMProviderProfile, String>
    ) -> Binding<String> {
        Binding(
            get: {
                settings.profile(for: providerID)[keyPath: keyPath]
            },
            set: { newValue in
                var profile = settings.profile(for: providerID)
                profile[keyPath: keyPath] = newValue
                settings.providerProfiles[providerID] = profile
            }
        )
    }

    private func voiceModelBinding(for providerID: LLMProviderID) -> Binding<String> {
        Binding(
            get: {
                switch providerID {
                case .gemini:
                    settings.voice.geminiModelID
                case .openAI:
                    settings.voice.openAIModelID
                }
            },
            set: { newValue in
                switch providerID {
                case .gemini:
                    settings.voice.geminiModelID = newValue
                case .openAI:
                    settings.voice.openAIModelID = newValue
                }
            }
        )
    }

    private func persistSettings(_ settings: LLMSettings) {
        settingsStore.saveSettings(settings)
        onSettingsChanged?()
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                appState.isLaunchAtLoginEnabled
            },
            set: { newValue in
                appState.setLaunchAtLoginEnabled(newValue)
            }
        )
    }

    private var selectedVoiceProviderID: LLMProviderID {
        settings.voice.providerID
    }

    private var selectedVoiceDefaultModelID: String {
        switch selectedVoiceProviderID {
        case .gemini:
            VoiceSettings.defaultGeminiModelID
        case .openAI:
            VoiceSettings.defaultOpenAIModelID
        }
    }
}
