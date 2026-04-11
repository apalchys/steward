import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var clipboardHistoryStore: ClipboardHistoryStore
    @State private var settings: LLMSettings
    @State private var showClearHistoryConfirmation = false

    private let settingsStore: any AppSettingsProviding
    private let onSettingsChanged: (() -> Void)?

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
        .frame(width: 760, height: 560)
        .onAppear {
            settings = settingsStore.loadSettings()
            appState.refreshLaunchAtLoginStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshLaunchAtLoginStatus()
        }
        .onChange(of: settings) { _, newSettings in
            normalizeAndPersist(newSettings)
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
            VStack(alignment: .leading, spacing: 20) {
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

                Divider()

                Text("Providers")
                    .font(.headline)

                Text("Set an API key to unlock that provider's compatible curated models on the feature tabs.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(LLMProviderID.allCases) { providerID in
                    providerCard(for: providerID)
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

                modelPickerSection(
                    title: "Model",
                    feature: .grammar,
                    selection: grammarModelBinding,
                    unavailableMessage: "Add a provider API key in General to unlock grammar models."
                )

                Text("Custom instructions for grammar check")
                    .font(.subheadline)

                TextEditor(text: $settings.grammar.customInstructions)
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

                modelPickerSection(
                    title: "Model",
                    feature: .screenText,
                    selection: screenTextModelBinding,
                    unavailableMessage: "Add a provider API key in General to unlock screen capture models."
                )

                Text("Custom instructions for screenshot to markdown")
                    .font(.subheadline)

                TextEditor(text: $settings.screenText.customInstructions)
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

    private var voiceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Voice Dictation")
                    .font(.headline)

                modelPickerSection(
                    title: "Model",
                    feature: .voice,
                    selection: voiceModelBinding,
                    unavailableMessage: "Add a provider API key in General to unlock dictation models."
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcut")
                        .font(.subheadline)

                    HotKeyRecorderView(
                        hotKey: $settings.voice.hotKey,
                        defaultHotKey: .defaultVoiceDictation,
                        validate: { appState.validateVoiceHotKey($0) }
                    )
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

                Text(
                    "Dictation keeps the spoken language(s), applies punctuation and formatting automatically, and uses push-to-talk: hold the shortcut to record, release to transcribe."
                )
                .font(.caption)
                .foregroundColor(.secondary)

                Text("Version 1 is optimized for recordings up to 120 seconds.")
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

    private func providerCard(for providerID: LLMProviderID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(providerID.displayName)
                    .font(.title3)
                    .bold()

                Spacer()

                Text(settings.providerSettings(for: providerID).isEnabled ? "Unlocked" : "Locked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ContinuousSecureField(
                placeholder: "\(providerID.displayName) API Key",
                text: providerAPIKeyBinding(for: providerID)
            )
            .frame(height: 22)

            VStack(alignment: .leading, spacing: 6) {
                Text("Curated models")
                    .font(.subheadline)

                ForEach(LLMModelCatalog.entries(for: providerID)) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(entry.modelID)
                            .font(.system(.body, design: .monospaced))

                        Spacer()

                        Text(entry.capabilitySummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func modelPickerSection(
        title: String,
        feature: LLMFeature,
        selection: Binding<LLMModelSelection?>,
        unavailableMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)

            let availableModels = settings.availableModels(for: feature)
            if availableModels.isEmpty {
                Text(unavailableMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Picker(title, selection: selection) {
                    ForEach(availableModels) { entry in
                        Text(entry.selection.pickerLabel)
                            .tag(Optional(entry.selection))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func normalizeAndPersist(_ newSettings: LLMSettings) {
        let normalizedSettings = newSettings.sanitized()

        if normalizedSettings != newSettings {
            settings = normalizedSettings
            return
        }

        settingsStore.saveSettings(normalizedSettings)
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

    private func providerAPIKeyBinding(for providerID: LLMProviderID) -> Binding<String> {
        Binding(
            get: {
                settings.providerSettings(for: providerID).apiKey
            },
            set: { newValue in
                var providerSettings = settings.providerSettings(for: providerID)
                providerSettings.apiKey = newValue
                settings.providerSettings[providerID] = providerSettings
            }
        )
    }

    private var grammarModelBinding: Binding<LLMModelSelection?> {
        Binding(
            get: {
                settings.grammar.selectedModel
            },
            set: { newValue in
                settings.grammar.selectedModel = newValue
            }
        )
    }

    private var screenTextModelBinding: Binding<LLMModelSelection?> {
        Binding(
            get: {
                settings.screenText.selectedModel
            },
            set: { newValue in
                settings.screenText.selectedModel = newValue
            }
        )
    }

    private var voiceModelBinding: Binding<LLMModelSelection?> {
        Binding(
            get: {
                settings.voice.selectedModel
            },
            set: { newValue in
                settings.voice.selectedModel = newValue
            }
        )
    }
}
