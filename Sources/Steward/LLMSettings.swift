import Foundation
import StewardCore

struct LLMProviderProfile: Equatable {
    var apiKey: String
    var modelID: String
    var baseURL: String

    static var empty: LLMProviderProfile {
        LLMProviderProfile(apiKey: "", modelID: "", baseURL: "")
    }

    var configuration: LLMProviderConfiguration? {
        let configuration = LLMProviderConfiguration(
            apiKey: apiKey.trimmed,
            modelID: modelID.trimmed,
            baseURL: baseURL.trimmed.isEmpty ? nil : baseURL.trimmed
        )

        return configuration.isConfigured ? configuration : nil
    }
}

struct LLMSettings: Equatable {
    var globalDefaultProviderID: LLMProviderID?
    var grammarProviderOverrideID: LLMProviderID?
    var ocrProviderOverrideID: LLMProviderID?
    var providerProfiles: [LLMProviderID: LLMProviderProfile]

    static func empty() -> LLMSettings {
        LLMSettings(
            globalDefaultProviderID: nil,
            grammarProviderOverrideID: nil,
            ocrProviderOverrideID: nil,
            providerProfiles: [:]
        )
    }

    func profile(for providerID: LLMProviderID) -> LLMProviderProfile {
        providerProfiles[providerID] ?? .empty
    }

    func configuration(for providerID: LLMProviderID) -> LLMProviderConfiguration? {
        profile(for: providerID).configuration
    }
}

protocol LLMSettingsProviding {
    func loadSettings() -> LLMSettings
    func saveSettings(_ settings: LLMSettings)
    func migrateLegacySettingsIfNeeded()
    func customGrammarRules() -> String
    func setCustomGrammarRules(_ value: String)
}

final class UserDefaultsLLMSettingsStore: LLMSettingsProviding {
    private enum Keys {
        static let migrated = "llmSettingsMigratedV1"
        static let globalDefaultProvider = "llm.globalDefaultProvider"
        static let grammarOverrideProvider = "llm.grammarProviderOverride"
        static let ocrOverrideProvider = "llm.ocrProviderOverride"
        static let customGrammarRules = "customGrammarRules"

        static func apiKey(for providerID: LLMProviderID) -> String {
            "llm.provider.\(providerID.rawValue).apiKey"
        }

        static func modelID(for providerID: LLMProviderID) -> String {
            "llm.provider.\(providerID.rawValue).modelID"
        }

        static func baseURL(for providerID: LLMProviderID) -> String {
            "llm.provider.\(providerID.rawValue).baseURL"
        }

        static let legacyOpenAIApiKey = "openAIApiKey"
        static let legacyOpenAIModelID = "openAIModelID"
        static let legacyGeminiAPIKey = "geminiAPIKey"
        static let legacyGeminiModelID = "geminiModelID"
    }

    static let supportedProviders: [LLMProviderID] = [.openAI, .gemini, .openAICompatible]

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSettings() -> LLMSettings {
        var profiles: [LLMProviderID: LLMProviderProfile] = [:]

        for providerID in Self.supportedProviders {
            profiles[providerID] = LLMProviderProfile(
                apiKey: userDefaults.string(forKey: Keys.apiKey(for: providerID)) ?? "",
                modelID: userDefaults.string(forKey: Keys.modelID(for: providerID)) ?? providerID.defaultModelID,
                baseURL: userDefaults.string(forKey: Keys.baseURL(for: providerID)) ?? ""
            )
        }

        return LLMSettings(
            globalDefaultProviderID: decodeProvider(from: Keys.globalDefaultProvider),
            grammarProviderOverrideID: decodeProvider(from: Keys.grammarOverrideProvider),
            ocrProviderOverrideID: decodeProvider(from: Keys.ocrOverrideProvider),
            providerProfiles: profiles
        )
    }

    func saveSettings(_ settings: LLMSettings) {
        encodeProvider(settings.globalDefaultProviderID, into: Keys.globalDefaultProvider)
        encodeProvider(settings.grammarProviderOverrideID, into: Keys.grammarOverrideProvider)
        encodeProvider(settings.ocrProviderOverrideID, into: Keys.ocrOverrideProvider)

        for providerID in Self.supportedProviders {
            let profile = settings.profile(for: providerID)
            userDefaults.set(profile.apiKey, forKey: Keys.apiKey(for: providerID))
            let normalizedModelID = profile.modelID.trimmed
            userDefaults.set(
                normalizedModelID.isEmpty ? providerID.defaultModelID : normalizedModelID,
                forKey: Keys.modelID(for: providerID)
            )
            userDefaults.set(profile.baseURL, forKey: Keys.baseURL(for: providerID))
        }
    }

    func migrateLegacySettingsIfNeeded() {
        guard !userDefaults.bool(forKey: Keys.migrated) else {
            return
        }

        var settings = loadSettings()

        let legacyOpenAIKey = userDefaults.string(forKey: Keys.legacyOpenAIApiKey)?.trimmed ?? ""
        let legacyOpenAIModel = normalizedPreferenceValue(
            forKey: Keys.legacyOpenAIModelID,
            defaultValue: LLMProviderID.openAI.defaultModelID
        )
        if settings.profile(for: .openAI).apiKey.trimmed.isEmpty && !legacyOpenAIKey.isEmpty {
            var profile = settings.profile(for: .openAI)
            profile.apiKey = legacyOpenAIKey
            profile.modelID = legacyOpenAIModel
            settings.providerProfiles[.openAI] = profile
        }

        let legacyGeminiKey = userDefaults.string(forKey: Keys.legacyGeminiAPIKey)?.trimmed ?? ""
        let legacyGeminiModel = normalizedPreferenceValue(
            forKey: Keys.legacyGeminiModelID,
            defaultValue: LLMProviderID.gemini.defaultModelID
        )
        if settings.profile(for: .gemini).apiKey.trimmed.isEmpty && !legacyGeminiKey.isEmpty {
            var profile = settings.profile(for: .gemini)
            profile.apiKey = legacyGeminiKey
            profile.modelID = legacyGeminiModel
            settings.providerProfiles[.gemini] = profile
        }

        if settings.globalDefaultProviderID == nil {
            if settings.configuration(for: .openAI) != nil {
                settings.globalDefaultProviderID = .openAI
            } else if settings.configuration(for: .gemini) != nil {
                settings.globalDefaultProviderID = .gemini
            }
        }

        saveSettings(settings)
        userDefaults.set(true, forKey: Keys.migrated)
    }

    func customGrammarRules() -> String {
        userDefaults.string(forKey: Keys.customGrammarRules) ?? ""
    }

    func setCustomGrammarRules(_ value: String) {
        userDefaults.set(value, forKey: Keys.customGrammarRules)
    }

    private func decodeProvider(from key: String) -> LLMProviderID? {
        guard let value = userDefaults.string(forKey: key) else {
            return nil
        }

        return LLMProviderID(rawValue: value)
    }

    private func encodeProvider(_ providerID: LLMProviderID?, into key: String) {
        if let providerID {
            userDefaults.set(providerID.rawValue, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func normalizedPreferenceValue(forKey key: String, defaultValue: String) -> String {
        let storedValue = userDefaults.string(forKey: key)?.trimmed

        if let storedValue, !storedValue.isEmpty {
            return storedValue
        }

        return defaultValue
    }
}
