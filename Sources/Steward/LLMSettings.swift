import Defaults
import Foundation
import OSLog
import StewardCore
import Valet

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.steward", category: "settings")

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
    var providerProfiles: [LLMProviderID: LLMProviderProfile]
    var grammarProviderID: LLMProviderID
    var screenshotProviderID: LLMProviderID

    static func empty() -> LLMSettings {
        LLMSettings(
            providerProfiles: [:],
            grammarProviderID: .openAI,
            screenshotProviderID: .gemini
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
    func customGrammarInstructions() -> String
    func setCustomGrammarInstructions(_ value: String)
    func customScreenshotInstructions() -> String
    func setCustomScreenshotInstructions(_ value: String)
}

protocol LLMSecretsStoring {
    func apiKey(for providerID: LLMProviderID) -> String
    func setAPIKey(_ apiKey: String, for providerID: LLMProviderID)
}

final class ValetLLMSecretsStore: LLMSecretsStoring {
    private enum Keys {
        static func apiKey(for providerID: LLMProviderID) -> String {
            "llmProvider_\(providerID.rawValue)_apiKey"
        }
    }

    private let valet: Valet

    init(valet: Valet = ValetLLMSecretsStore.makeDefaultValet()) {
        self.valet = valet
    }

    func apiKey(for providerID: LLMProviderID) -> String {
        (try? valet.string(forKey: Keys.apiKey(for: providerID))) ?? ""
    }

    func setAPIKey(_ apiKey: String, for providerID: LLMProviderID) {
        let normalizedValue = apiKey.trimmed
        let key = Keys.apiKey(for: providerID)

        do {
            if normalizedValue.isEmpty {
                try valet.removeObject(forKey: key)
            } else {
                try valet.setString(normalizedValue, forKey: key)
            }
        } catch {
            logger.error("ValetLLMSecretsStore write failed for \(providerID.rawValue): \(error)")
        }
    }

    private static func makeDefaultValet() -> Valet {
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
            let identifier = Identifier(nonEmpty: "\(bundleIdentifier)_llm")
        {
            return Valet.valet(with: identifier, accessibility: .whenUnlocked)
        }

        guard let fallbackIdentifier = Identifier(nonEmpty: "Steward_llm") else {
            preconditionFailure("Could not build Valet identifier for LLM secrets")
        }

        return Valet.valet(with: fallbackIdentifier, accessibility: .whenUnlocked)
    }
}

final class UserDefaultsLLMSettingsStore: LLMSettingsProviding {
    static let supportedProviders: [LLMProviderID] = [.openAI, .gemini]

    private struct Keys {
        let grammarProviderID: Defaults.Key<String>
        let screenshotProviderID: Defaults.Key<String>
        let customGrammarInstructions: Defaults.Key<String>
        let customScreenshotInstructions: Defaults.Key<String>
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
        }

        func modelID(for providerID: LLMProviderID) -> Defaults.Key<String> {
            Defaults.Key<String>(
                "llmProvider_\(providerID.rawValue)_modelID",
                default: providerID.defaultModelID,
                suite: userDefaults
            )
        }

        func baseURL(for providerID: LLMProviderID) -> Defaults.Key<String> {
            Defaults.Key<String>(
                "llmProvider_\(providerID.rawValue)_baseURL",
                default: "",
                suite: userDefaults
            )
        }
    }

    private let keys: Keys
    private let secretsStore: any LLMSecretsStoring

    init(
        userDefaults: UserDefaults = .standard,
        secretsStore: any LLMSecretsStoring = ValetLLMSecretsStore()
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
                modelID: modelID,
                baseURL: Defaults[keys.baseURL(for: providerID)]
            )
        }

        let grammarProviderID = validatedProviderID(
            rawValue: Defaults[keys.grammarProviderID],
            fallback: .openAI
        )
        let screenshotProviderID = validatedProviderID(
            rawValue: Defaults[keys.screenshotProviderID],
            fallback: .gemini
        )

        return LLMSettings(
            providerProfiles: profiles,
            grammarProviderID: grammarProviderID,
            screenshotProviderID: screenshotProviderID
        )
    }

    func saveSettings(_ settings: LLMSettings) {
        for providerID in Self.supportedProviders {
            let profile = settings.profile(for: providerID)

            secretsStore.setAPIKey(profile.apiKey, for: providerID)

            let normalizedModelID = profile.modelID.trimmed
            Defaults[keys.modelID(for: providerID)] =
                normalizedModelID.isEmpty ? providerID.defaultModelID : normalizedModelID
            Defaults[keys.baseURL(for: providerID)] = profile.baseURL
        }

        Defaults[keys.grammarProviderID] = settings.grammarProviderID.rawValue
        Defaults[keys.screenshotProviderID] = settings.screenshotProviderID.rawValue
    }

    func migrateLegacySettingsIfNeeded() {
        // Migration intentionally disabled in the current iteration.
    }

    func customGrammarInstructions() -> String {
        Defaults[keys.customGrammarInstructions]
    }

    func setCustomGrammarInstructions(_ value: String) {
        Defaults[keys.customGrammarInstructions] = value
    }

    func customScreenshotInstructions() -> String {
        Defaults[keys.customScreenshotInstructions]
    }

    func setCustomScreenshotInstructions(_ value: String) {
        Defaults[keys.customScreenshotInstructions] = value
    }

    private func validatedProviderID(rawValue: String, fallback: LLMProviderID) -> LLMProviderID {
        guard
            let providerID = LLMProviderID(rawValue: rawValue),
            Self.supportedProviders.contains(providerID)
        else {
            return fallback
        }

        return providerID
    }
}
