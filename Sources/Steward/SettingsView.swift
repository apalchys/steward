import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var settings: LLMSettings
    @State private var grammarInstructions: String
    @State private var screenshotInstructions: String

    private let settingsStore: any LLMSettingsProviding
    private let onSettingsChanged: (() -> Void)?

    init(
        settingsStore: any LLMSettingsProviding = UserDefaultsLLMSettingsStore(),
        onSettingsChanged: (() -> Void)? = nil
    ) {
        self.settingsStore = settingsStore
        self.onSettingsChanged = onSettingsChanged
        _settings = State(initialValue: settingsStore.loadSettings())
        _grammarInstructions = State(initialValue: settingsStore.customGrammarInstructions())
        _screenshotInstructions = State(initialValue: settingsStore.customScreenshotInstructions())
    }

    var body: some View {
        TabView {
            grammarTab
                .tabItem {
                    Label("Grammar", systemImage: "text.book.closed")
                }

            screenshotTab
                .tabItem {
                    Label("Screenshot", systemImage: "photo.on.rectangle")
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
            grammarInstructions = settingsStore.customGrammarInstructions()
            screenshotInstructions = settingsStore.customScreenshotInstructions()
        }
        .onChange(of: settings) { _, newSettings in
            settingsStore.saveSettings(newSettings)
            onSettingsChanged?()
        }
        .onChange(of: grammarInstructions) { _, newValue in
            settingsStore.setCustomGrammarInstructions(newValue)
            onSettingsChanged?()
        }
        .onChange(of: screenshotInstructions) { _, newValue in
            settingsStore.setCustomScreenshotInstructions(newValue)
            onSettingsChanged?()
        }
    }

    private var grammarTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Grammar")
                    .font(.headline)

                Picker("Provider", selection: $settings.grammarProviderID) {
                    ForEach(providerOptions(for: .textCorrection)) { providerID in
                        Text(providerID.displayName).tag(providerID)
                    }
                }
                .pickerStyle(.segmented)

                SecureField(
                    "\(settings.grammarProviderID.displayName) API Key",
                    text: profileBinding(for: settings.grammarProviderID, keyPath: \.apiKey)
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Model (default: \(settings.grammarProviderID.defaultModelID))",
                    text: profileBinding(for: settings.grammarProviderID, keyPath: \.modelID)
                )
                .textFieldStyle(.roundedBorder)

                Text("Custom instructions for grammar check")
                    .font(.subheadline)

                TextEditor(text: $grammarInstructions)
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

                Picker("Provider", selection: $settings.screenshotProviderID) {
                    ForEach(providerOptions(for: .visionOCR)) { providerID in
                        Text(providerID.displayName).tag(providerID)
                    }
                }
                .pickerStyle(.segmented)

                SecureField(
                    "\(settings.screenshotProviderID.displayName) API Key",
                    text: profileBinding(for: settings.screenshotProviderID, keyPath: \.apiKey)
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Model (default: \(settings.screenshotProviderID.defaultModelID))",
                    text: profileBinding(for: settings.screenshotProviderID, keyPath: \.modelID)
                )
                .textFieldStyle(.roundedBorder)

                Text("Custom instructions for screenshot to markdown")
                    .font(.subheadline)

                TextEditor(text: $screenshotInstructions)
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

    private func providerOptions(for capability: LLMCapability) -> [LLMProviderID] {
        LLMProviderID.allCases.filter { $0.capabilities.contains(capability) }
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
