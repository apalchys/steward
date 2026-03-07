import SwiftUI

struct SettingsView: View {
    @State private var settings = UserDefaultsLLMSettingsStore().loadSettings()
    @State private var customRules = UserDefaultsLLMSettingsStore().customGrammarRules()

    private let settingsStore = UserDefaultsLLMSettingsStore()

    private var grammarProviderOptions: [LLMProviderID] {
        UserDefaultsLLMSettingsStore.supportedProviders.filter { $0.capabilities.contains(.textCorrection) }
    }

    private var ocrProviderOptions: [LLMProviderID] {
        UserDefaultsLLMSettingsStore.supportedProviders.filter { $0.capabilities.contains(.visionOCR) }
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            customRulesTab
                .tabItem {
                    Label("Custom Rules", systemImage: "list.bullet.rectangle")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 760, height: 520)
        .onAppear {
            settingsStore.migrateLegacySettingsIfNeeded()
            settings = settingsStore.loadSettings()
            customRules = settingsStore.customGrammarRules()
        }
        .onChange(of: settings) { newSettings in
            settingsStore.saveSettings(newSettings)
            NotificationCenter.default.post(name: .checkGrammarProviderStatus, object: nil)
            NotificationCenter.default.post(name: .checkOCRProviderStatus, object: nil)
        }
        .onChange(of: customRules) { newValue in
            settingsStore.setCustomGrammarRules(newValue)
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                providerRoutingSection
                Divider()
                providerProfileSection(for: .openAI)
                providerProfileSection(for: .gemini)
                providerProfileSection(for: .openAICompatible)
            }
            .padding(20)
        }
    }

    private var providerRoutingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LLM Routing")
                .font(.headline)

            Picker(
                "Global default provider",
                selection: Binding<LLMProviderID?>(
                    get: { settings.globalDefaultProviderID },
                    set: { settings.globalDefaultProviderID = $0 }
                )
            ) {
                Text("Automatic").tag(Optional<LLMProviderID>.none)
                ForEach(UserDefaultsLLMSettingsStore.supportedProviders) { providerID in
                    Text(providerID.displayName).tag(Optional(providerID))
                }
            }

            Picker(
                "Grammar provider override",
                selection: Binding<LLMProviderID?>(
                    get: { settings.grammarProviderOverrideID },
                    set: { settings.grammarProviderOverrideID = $0 }
                )
            ) {
                Text("Use global default").tag(Optional<LLMProviderID>.none)
                ForEach(grammarProviderOptions) { providerID in
                    Text(providerID.displayName).tag(Optional(providerID))
                }
            }

            Picker(
                "OCR provider override",
                selection: Binding<LLMProviderID?>(
                    get: { settings.ocrProviderOverrideID },
                    set: { settings.ocrProviderOverrideID = $0 }
                )
            ) {
                Text("Use global default").tag(Optional<LLMProviderID>.none)
                ForEach(ocrProviderOptions) { providerID in
                    Text(providerID.displayName).tag(Optional(providerID))
                }
            }

            Text("OCR picker only shows providers with vision capability.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func providerProfileSection(for providerID: LLMProviderID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(providerID.displayName)
                .font(.headline)

            SecureField("API Key", text: profileBinding(for: providerID, keyPath: \.apiKey))
                .textFieldStyle(.roundedBorder)

            TextField("Model ID (default: \(providerID.defaultModelID))", text: profileBinding(for: providerID, keyPath: \.modelID))
                .textFieldStyle(.roundedBorder)

            if providerID == .openAICompatible {
                TextField("Base URL (example: https://api.example.com)", text: profileBinding(for: providerID, keyPath: \.baseURL))
                    .textFieldStyle(.roundedBorder)
            }

            Text(providerDescription(for: providerID))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var customRulesTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Custom Grammar Rules")
                .font(.headline)

            TextEditor(text: $customRules)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

            Text("These rules are appended to grammar correction prompts for providers that support text correction.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(20)
    }

    private var aboutTab: some View {
        VStack(alignment: .center, spacing: 12) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            } else if let iconImage = Bundle.main.decodedImage(named: "icon") {
                iconImage
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

            Text("Modular architecture with swappable LLM backends")
                .font(.subheadline)
                .foregroundColor(.secondary)

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

    private func providerDescription(for providerID: LLMProviderID) -> String {
        switch providerID {
        case .openAI:
            return "Native OpenAI Responses API provider for grammar correction."
        case .gemini:
            return "Native Gemini provider for screen OCR extraction."
        case .anthropic:
            return "Anthropic profile is reserved for future support."
        case .openAICompatible:
            return "Use any OpenAI-compatible endpoint by setting API key, model, and base URL."
        }
    }
}

extension Bundle {
    func decodedImage(named name: String) -> Image? {
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
            let nsImage = NSImage(contentsOfFile: path)
        {
            return Image(nsImage: nsImage)
        }

        return nil
    }
}
