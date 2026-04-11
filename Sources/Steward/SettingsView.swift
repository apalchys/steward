import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var clipboardHistoryStore: ClipboardHistoryStore
    @State private var settings: LLMSettings
    @State private var selectedPane: SettingsPane = .general
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
        HStack(spacing: 0) {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                SettingsSidebarRow(pane: pane)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 232)
            .background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    paneHeader
                    paneContent
                }
                .frame(maxWidth: 740, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(
            minWidth: 820, idealWidth: 900, maxWidth: .infinity, minHeight: 620, idealHeight: 620, maxHeight: .infinity
        )
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

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedPane.title)
                .font(.system(size: 30, weight: .semibold))

            if let description = selectedPane.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .general:
            generalPane
        case .providers:
            providersPane
        case .grammar:
            featurePane(
                title: "Refine",
                featureDescription: "Pick a Refine model and optional instructions for rewrite guidance.",
                feature: .grammar,
                selection: grammarModelBinding,
                instructions: $settings.grammar.customInstructions,
                emptyStateMessage: "Add a provider API key in Providers to unlock Refine models.",
                instructionsTitle: "Custom instructions",
                instructionsDescription: "Optional guidance applied when Steward refines selected text.",
                footer: "Steward preserves your text intent and applies the model you choose here."
            )
        case .screenText:
            featurePane(
                title: "Capture",
                featureDescription: "Choose a model for OCR and optional formatting instructions.",
                feature: .screenText,
                selection: screenTextModelBinding,
                instructions: $settings.screenText.customInstructions,
                emptyStateMessage: "Add a provider API key in Providers to unlock Capture models.",
                instructionsTitle: "Custom instructions",
                instructionsDescription:
                    "Optional guidance applied when Capture converts selected content into Markdown.",
                footer: "Use concise instructions to control headings, lists, and formatting."
            )
        case .voice:
            voicePane
        case .clipboard:
            clipboardPane
        case .about:
            aboutPane
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionCard {
                SettingsRow(
                    title: "Launch Steward at login",
                    description: "Steward uses macOS Login Items and follows your system-level preference."
                ) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .disabled(appState.isUpdatingLaunchAtLogin)
                }

                SettingsInsetDivider()

                if let launchAtLoginMessage = appState.launchAtLoginMessage {
                    SettingsInfoRow(text: launchAtLoginMessage)
                    SettingsInsetDivider()
                }

                if appState.shouldShowOpenLoginItemsAction {
                    SettingsButtonRow(
                        title: "Login Items",
                        description: "Open System Settings if Steward cannot update the login item directly.",
                        buttonTitle: "Open Login Items Settings",
                        action: appState.openLoginItemsSettings
                    )
                }
            }

            SettingsSectionCard {
                SettingsInfoRow(
                    text:
                        "Provider setup moved to Providers. Configure API keys there, then return here to manage app behavior."
                )
            }
        }
    }

    private var providersPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(LLMProviderID.allCases) { providerID in
                providerCard(for: providerID)
            }
        }
    }

    private var voicePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            featurePane(
                title: "Dictate",
                featureDescription: "Choose a transcription model and optional instructions for Dictate cleanup.",
                feature: .voice,
                selection: voiceModelBinding,
                instructions: $settings.voice.customInstructions,
                emptyStateMessage: "Add a provider API key in Providers to unlock Dictate models.",
                instructionsTitle: "Custom instructions",
                instructionsDescription: "Optional guidance applied after speech is transcribed.",
                footer: "Dictate keeps the spoken language, applies punctuation, and formats text automatically."
            )

            SettingsSectionCard(
                title: "Shortcut",
                description: "Hold the shortcut to record. Release to transcribe."
            ) {
                HotKeyRecorderView(
                    hotKey: $settings.voice.hotKey,
                    defaultHotKey: .defaultVoiceDictation,
                    validate: { appState.validateVoiceHotKey($0) }
                )
            }

            Text("Version 1 is optimized for recordings up to 120 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var clipboardPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionCard {
                SettingsRow(
                    title: "Clipboard history",
                    description: "Store copied text locally on this Mac. New entries stop immediately when disabled."
                ) {
                    Toggle("", isOn: $settings.clipboardHistory.isEnabled)
                        .labelsHidden()
                }

                SettingsInsetDivider()

                SettingsRow(
                    title: "Retention",
                    description: "Older entries are removed automatically once the limit is reached."
                ) {
                    Stepper(
                        value: $settings.clipboardHistory.maxStoredRecords,
                        in: 1...ClipboardHistorySettings.maxStoredRecordsLimit,
                        step: ClipboardHistorySettings.maxStoredRecordsStep
                    ) {
                        Text("\(settings.clipboardHistory.maxStoredRecords)")
                            .monospacedDigit()
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                    .disabled(!settings.clipboardHistory.isEnabled)
                }

                SettingsInsetDivider()

                SettingsValueRow(
                    title: "Storage path",
                    description: "Append-only local store used for clipboard history.",
                    value: ClipboardHistoryStore.defaultHistoryFileURL().path
                )
            }

            SettingsSectionCard {
                SettingsButtonRow(
                    title: "Clear stored history",
                    description: "Delete all existing clipboard records. This cannot be undone.",
                    buttonTitle: "Clear History",
                    role: .destructive,
                    isDisabled: clipboardHistoryStore.records.isEmpty
                ) {
                    showClearHistoryConfirmation = true
                }
            }
        }
    }

    private var aboutPane: some View {
        SettingsSectionCard {
            VStack(alignment: .center, spacing: 16) {
                appIconView

                VStack(spacing: 6) {
                    Text("Steward")
                        .font(.system(size: 28, weight: .semibold))

                    Text("Steward helps you polish writing and turn screenshot text into clean Markdown in seconds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                VStack(spacing: 4) {
                    Text("Version \(Bundle.main.releaseVersionNumber) (\(Bundle.main.buildVersionNumber))")
                        .font(.subheadline.weight(.medium))

                    Text(Bundle.main.bundleIdentifier ?? "com.steward")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func featurePane(
        title: String,
        featureDescription: String,
        feature: LLMFeature,
        selection: Binding<LLMModelSelection?>,
        instructions: Binding<String>,
        emptyStateMessage: String,
        instructionsTitle: String,
        instructionsDescription: String,
        footer: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionCard(
                title: "Model",
                description: featureDescription
            ) {
                modelPickerRow(
                    feature: feature,
                    selection: selection,
                    emptyStateMessage: emptyStateMessage
                )
            }

            SettingsEditorCard(
                title: instructionsTitle,
                description: instructionsDescription,
                text: instructions
            )

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func providerCard(for providerID: LLMProviderID) -> some View {
        let providerSettings = settings.providerSettings(for: providerID)
        let models = LLMModelCatalog.entries(for: providerID)

        return SettingsSectionCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(providerID.displayName)
                        .font(.title3.weight(.semibold))

                    Text(
                        "Add an API key to unlock curated \(providerID.displayName) models across Refine, Capture, and Dictate."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(providerSettings.isEnabled ? "Unlocked" : "Locked")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(providerSettings.isEnabled ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                providerSettings.isEnabled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
                    )
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("API key")
                    .font(.subheadline.weight(.medium))

                ContinuousSecureField(
                    placeholder: "\(providerID.displayName) API Key",
                    text: providerAPIKeyBinding(for: providerID)
                )
                .frame(height: 22)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Available models")
                    .font(.subheadline.weight(.medium))

                ForEach(models) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(entry.modelID)
                                .font(.system(.body, design: .monospaced))

                            Spacer(minLength: 12)

                            Text(entry.capabilitySummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        if entry.id != models.last?.id {
                            Divider()
                                .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelPickerRow(
        feature: LLMFeature,
        selection: Binding<LLMModelSelection?>,
        emptyStateMessage: String
    ) -> some View {
        let availableModels = settings.availableModels(for: feature)

        if availableModels.isEmpty {
            SettingsInfoRow(text: emptyStateMessage)
        } else {
            SettingsRow(
                title: "Selected model",
                description: "Only models compatible with this feature are shown."
            ) {
                Picker("Selected model", selection: selection) {
                    ForEach(availableModels) { entry in
                        Text(entry.selection.pickerLabel)
                            .tag(Optional(entry.selection))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 280, alignment: .trailing)
            }
        }
    }

    private var appIconView: some View {
        Group {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
            } else if let iconURL = Bundle.main.url(forResource: "icon", withExtension: "png")
                ?? Bundle.main.resourceURL?.appendingPathComponent("icon.png"),
                let iconImage = NSImage(contentsOf: iconURL)
            {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
            } else {
                Image(systemName: "pencil.and.outline")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.tint)
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

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case providers
    case grammar
    case screenText
    case voice
    case clipboard
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .providers:
            return "Providers"
        case .grammar:
            return "Refine"
        case .screenText:
            return "Capture"
        case .voice:
            return "Dictate"
        case .clipboard:
            return "Clipboard"
        case .about:
            return "About"
        }
    }

    var description: String? {
        switch self {
        case .general:
            return "App-level behavior and launch preferences."
        case .providers:
            return "Manage API keys and review curated provider model coverage."
        case .grammar:
            return "Model and prompt settings for text refinement."
        case .screenText:
            return "Model and prompt settings for capture-to-Markdown extraction."
        case .voice:
            return "Model, shortcut, and prompt settings for Dictate push-to-talk."
        case .clipboard:
            return "Local clipboard history capture, retention, and cleanup."
        case .about:
            return "App identity and build information."
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .providers:
            return "key.horizontal"
        case .grammar:
            return "text.book.closed"
        case .screenText:
            return "text.viewfinder"
        case .voice:
            return "waveform"
        case .clipboard:
            return "clipboard"
        case .about:
            return "info.circle"
        }
    }

}

private struct SettingsSectionCard<Content: View>: View {
    let title: String?
    let description: String?
    let content: Content

    init(
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    if let description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
        )
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 22, alignment: .center)

            Text(pane.title)
                .font(.title3.weight(.medium))

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private struct SettingsInsetDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 0)
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let description: String
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        description: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.description = description
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            accessory
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let description: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.medium))

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct SettingsInfoRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsButtonRow: View {
    let title: String
    let description: String
    let buttonTitle: String
    var role: ButtonRole?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        SettingsRow(title: title, description: description) {
            Button(buttonTitle, role: role, action: action)
                .disabled(isDisabled)
        }
    }
}

private struct SettingsEditorCard: View {
    let title: String
    let description: String
    @Binding var text: String

    var body: some View {
        SettingsSectionCard(title: title, description: description) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
        }
    }
}

private extension Bundle {
    var releaseVersionNumber: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var buildVersionNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
