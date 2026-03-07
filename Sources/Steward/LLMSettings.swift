import Defaults
import Foundation
import OSLog
import StewardCore

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.steward", category: "settings")

struct LLMProviderProfile: Equatable {
    var apiKey: String
    var modelID: String

    static var empty: LLMProviderProfile {
        LLMProviderProfile(apiKey: "", modelID: "")
    }

    var configuration: LLMProviderConfiguration? {
        let configuration = LLMProviderConfiguration(
            apiKey: apiKey.trimmed,
            modelID: modelID.trimmed
        )

        return configuration.isConfigured ? configuration : nil
    }
}

struct LLMSettings: Equatable {
    static let grammarProvider = LLMProviderID.openAI
    static let screenshotProvider = LLMProviderID.gemini

    var providerProfiles: [LLMProviderID: LLMProviderProfile]
    var grammarProviderID: LLMProviderID
    var screenshotProviderID: LLMProviderID
    var grammarCustomInstructions: String
    var screenshotCustomInstructions: String
    var clipboardHistory: ClipboardHistorySettings

    static func empty() -> LLMSettings {
        LLMSettings(
            providerProfiles: [:],
            grammarProviderID: grammarProvider,
            screenshotProviderID: screenshotProvider,
            grammarCustomInstructions: "",
            screenshotCustomInstructions: "",
            clipboardHistory: .default
        )
    }

    func normalizedProviders() -> LLMSettings {
        var copy = self
        copy.grammarProviderID = Self.grammarProvider
        copy.screenshotProviderID = Self.screenshotProvider
        return copy
    }

    func profile(for providerID: LLMProviderID) -> LLMProviderProfile {
        providerProfiles[providerID] ?? .empty
    }

    func configuration(for providerID: LLMProviderID) -> LLMProviderConfiguration? {
        profile(for: providerID).configuration
    }
}

struct ClipboardHistorySettings: Equatable {
    static let defaultMaxStoredRecords = 100
    static let `default` = ClipboardHistorySettings()

    var isEnabled: Bool
    var maxStoredRecords: Int

    init(isEnabled: Bool = false, maxStoredRecords: Int = ClipboardHistorySettings.defaultMaxStoredRecords) {
        self.isEnabled = isEnabled
        self.maxStoredRecords = Self.sanitizedMaxStoredRecords(maxStoredRecords)
    }

    static func sanitizedMaxStoredRecords(_ value: Int) -> Int {
        max(1, value)
    }
}

protocol AppSettingsProviding {
    func loadSettings() -> LLMSettings
    func saveSettings(_ settings: LLMSettings)
}

protocol LLMSecretsStoring {
    func apiKey(for providerID: LLMProviderID) -> String
    func setAPIKey(_ apiKey: String, for providerID: LLMProviderID)
}

final class UserDefaultsLLMSecretsStore: LLMSecretsStoring {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func apiKey(for providerID: LLMProviderID) -> String {
        (userDefaults.string(forKey: key(for: providerID)) ?? "").trimmed
    }

    func setAPIKey(_ apiKey: String, for providerID: LLMProviderID) {
        let normalized = apiKey.trimmed
        if normalized.isEmpty {
            userDefaults.removeObject(forKey: key(for: providerID))
        } else {
            userDefaults.set(normalized, forKey: key(for: providerID))
        }
    }

    private func key(for providerID: LLMProviderID) -> String {
        "llmProvider_\(providerID.rawValue)_apiKey"
    }
}

final class UserDefaultsLLMSettingsStore: AppSettingsProviding {
    static let supportedProviders: [LLMProviderID] = [.openAI, .gemini]

    private struct Keys {
        let grammarProviderID: Defaults.Key<String>
        let screenshotProviderID: Defaults.Key<String>
        let customGrammarInstructions: Defaults.Key<String>
        let customScreenshotInstructions: Defaults.Key<String>
        let clipboardHistoryEnabled: Defaults.Key<Bool>
        let clipboardHistoryMaxStoredRecords: Defaults.Key<Int>
        let userDefaults: UserDefaults

        init(userDefaults: UserDefaults) {
            self.userDefaults = userDefaults
            grammarProviderID = Defaults.Key<String>(
                "llmProvider_grammar",
                default: LLMProviderID.openAI.rawValue,
                suite: userDefaults
            )
            screenshotProviderID = Defaults.Key<String>(
                "llmProvider_screenshot",
                default: LLMProviderID.gemini.rawValue,
                suite: userDefaults
            )
            customGrammarInstructions = Defaults.Key<String>(
                "customGrammarInstructions",
                default: "",
                suite: userDefaults
            )
            customScreenshotInstructions = Defaults.Key<String>(
                "customScreenshotInstructions",
                default: "",
                suite: userDefaults
            )
            clipboardHistoryEnabled = Defaults.Key<Bool>(
                "clipboardHistoryEnabled",
                default: ClipboardHistorySettings.default.isEnabled,
                suite: userDefaults
            )
            clipboardHistoryMaxStoredRecords = Defaults.Key<Int>(
                "clipboardHistoryMaxStoredRecords",
                default: ClipboardHistorySettings.default.maxStoredRecords,
                suite: userDefaults
            )
        }

        func modelID(for providerID: LLMProviderID) -> Defaults.Key<String> {
            Defaults.Key<String>(
                "llmProvider_\(providerID.rawValue)_modelID",
                default: providerID.defaultModelID,
                suite: userDefaults
            )
        }

    }

    private let keys: Keys
    private let secretsStore: any LLMSecretsStoring

    init(
        userDefaults: UserDefaults = .standard,
        secretsStore: any LLMSecretsStoring = UserDefaultsLLMSecretsStore()
    ) {
        self.keys = Keys(userDefaults: userDefaults)
        self.secretsStore = secretsStore
    }

    func loadSettings() -> LLMSettings {
        var profiles: [LLMProviderID: LLMProviderProfile] = [:]

        for providerID in Self.supportedProviders {
            let rawModelID = Defaults[keys.modelID(for: providerID)].trimmed
            let modelID = rawModelID.isEmpty ? providerID.defaultModelID : rawModelID

            profiles[providerID] = LLMProviderProfile(
                apiKey: secretsStore.apiKey(for: providerID),
                modelID: modelID
            )
        }

        return LLMSettings(
            providerProfiles: profiles,
            grammarProviderID: LLMSettings.grammarProvider,
            screenshotProviderID: LLMSettings.screenshotProvider,
            grammarCustomInstructions: Defaults[keys.customGrammarInstructions],
            screenshotCustomInstructions: Defaults[keys.customScreenshotInstructions],
            clipboardHistory: ClipboardHistorySettings(
                isEnabled: Defaults[keys.clipboardHistoryEnabled],
                maxStoredRecords: Defaults[keys.clipboardHistoryMaxStoredRecords]
            )
        )
        .normalizedProviders()
    }

    func saveSettings(_ settings: LLMSettings) {
        let normalizedSettings = settings.normalizedProviders()

        for providerID in Self.supportedProviders {
            let profile = normalizedSettings.profile(for: providerID)

            secretsStore.setAPIKey(profile.apiKey, for: providerID)

            let normalizedModelID = profile.modelID.trimmed
            Defaults[keys.modelID(for: providerID)] =
                normalizedModelID.isEmpty ? providerID.defaultModelID : normalizedModelID
        }

        Defaults[keys.grammarProviderID] = LLMSettings.grammarProvider.rawValue
        Defaults[keys.screenshotProviderID] = LLMSettings.screenshotProvider.rawValue
        Defaults[keys.customGrammarInstructions] = normalizedSettings.grammarCustomInstructions
        Defaults[keys.customScreenshotInstructions] = normalizedSettings.screenshotCustomInstructions
        Defaults[keys.clipboardHistoryEnabled] = normalizedSettings.clipboardHistory.isEnabled
        Defaults[keys.clipboardHistoryMaxStoredRecords] = normalizedSettings.clipboardHistory.maxStoredRecords
    }
}
