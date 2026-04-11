import AppKit
import Foundation
import HotKey
import XCTest
@testable import Steward
@testable import StewardCore

final class LLMSettingsMigrationTests: XCTestCase {
    func testUserDefaultsSecretsStorePersistsAndDeletesAPIKeys() {
        let suiteName = "StewardTests.secrets.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsLLMSecretsStore(userDefaults: defaults)

        XCTAssertEqual(store.apiKey(for: .openAI), "")

        store.setAPIKey(" sk-test ", for: .openAI)

        let reloadedStore = UserDefaultsLLMSecretsStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.apiKey(for: .openAI), "sk-test")

        reloadedStore.setAPIKey("", for: .openAI)

        let clearedStore = UserDefaultsLLMSecretsStore(userDefaults: defaults)
        XCTAssertEqual(clearedStore.apiKey(for: .openAI), "")
    }

    func testSaveAndLoadRoundTripsProviderKeysFeatureSelectionsAndHotKey() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let secretsStore = InMemoryLLMSecretsStore()
        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: secretsStore)

        var settings = LLMSettings.empty()
        settings.providerSettings[.openAI] = LLMProviderSettings(apiKey: "openai-key")
        settings.providerSettings[.gemini] = LLMProviderSettings(apiKey: "gemini-key")
        settings.grammar = GrammarSettings(
            selectedModel: LLMModelSelection(providerID: .openAI, modelID: OpenAIClient.defaultModelID),
            customInstructions: "Rule 1\nRule 2"
        )
        settings.screenText = ScreenTextSettings(
            selectedModel: LLMModelSelection(providerID: .gemini, modelID: GeminiClient.defaultModelID),
            customInstructions: "Keep bullet lists"
        )
        settings.voice = VoiceSettings(
            selectedModel: LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe"),
            customInstructions: "Keep speaker intent",
            hotKey: AppHotKey(
                carbonKeyCode: Key.v.carbonKeyCode,
                carbonModifiers: NSEvent.ModifierFlags([.command, .option]).carbonFlags
            )
        )
        settings.clipboardHistory = ClipboardHistorySettings(isEnabled: true, maxStoredRecords: 250)

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.providerSettings(for: .openAI).apiKey, "openai-key")
        XCTAssertEqual(loaded.providerSettings(for: .gemini).apiKey, "gemini-key")
        XCTAssertEqual(loaded.grammar, settings.grammar)
        XCTAssertEqual(loaded.screenText, settings.screenText)
        XCTAssertEqual(loaded.voice, settings.voice)
        XCTAssertEqual(loaded.clipboardHistory, ClipboardHistorySettings(isEnabled: true, maxStoredRecords: 250))
    }

    func testLoadSettingsDefaultsToUnconfiguredSelectionsWhenNoProvidersEnabled() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())

        let settings = store.loadSettings()

        XCTAssertEqual(settings.grammar.customInstructions, "")
        XCTAssertEqual(settings.screenText.customInstructions, "")
        XCTAssertNil(settings.grammar.selectedModel)
        XCTAssertNil(settings.screenText.selectedModel)
        XCTAssertNil(settings.voice.selectedModel)
        XCTAssertEqual(settings.voice.hotKey, .defaultVoiceDictation)
        XCTAssertEqual(settings.clipboardHistory, .default)
    }

    func testLoadSettingsMigratesLegacySelections() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(LLMProviderID.openAI.rawValue, forKey: "voiceProviderID")
        defaults.set("gpt-4o-mini-transcribe", forKey: "voiceOpenAIModelID")

        let secretsStore = InMemoryLLMSecretsStore(
            values: [.openAI: "openai-key", .gemini: "gemini-key"]
        )
        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: secretsStore)

        let settings = store.loadSettings()

        XCTAssertEqual(
            settings.grammar.selectedModel,
            LLMModelSelection(providerID: .openAI, modelID: OpenAIClient.defaultModelID)
        )
        XCTAssertEqual(
            settings.screenText.selectedModel,
            LLMModelSelection(providerID: .gemini, modelID: GeminiClient.defaultModelID)
        )
        XCTAssertEqual(
            settings.voice.selectedModel,
            LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe")
        )
    }

    func testLoadSettingsFallsBackWhenLegacyModelIsNotInCatalog() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("not-in-catalog", forKey: "llmProvider_openAI_modelID")
        defaults.set("not-in-catalog", forKey: "llmProvider_gemini_modelID")
        defaults.set(LLMProviderID.openAI.rawValue, forKey: "voiceProviderID")
        defaults.set("not-in-catalog", forKey: "voiceOpenAIModelID")

        let secretsStore = InMemoryLLMSecretsStore(
            values: [.openAI: "openai-key"]
        )
        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: secretsStore)

        let settings = store.loadSettings()

        XCTAssertEqual(
            settings.grammar.selectedModel,
            LLMModelSelection(providerID: .openAI, modelID: OpenAIClient.defaultModelID)
        )
        XCTAssertEqual(
            settings.screenText.selectedModel,
            LLMModelSelection(providerID: .openAI, modelID: OpenAIClient.defaultModelID)
        )
        XCTAssertEqual(
            settings.voice.selectedModel,
            LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe")
        )
    }

    func testSaveSettingsRemovesLegacyModelKeys() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("legacy-openai-model", forKey: "llmProvider_openAI_modelID")
        defaults.set("legacy-gemini-model", forKey: "llmProvider_gemini_modelID")
        defaults.set(LLMProviderID.openAI.rawValue, forKey: "voiceProviderID")
        defaults.set("legacy-voice-model", forKey: "voiceOpenAIModelID")

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        store.saveSettings(.empty())

        XCTAssertNil(defaults.object(forKey: "llmProvider_openAI_modelID"))
        XCTAssertNil(defaults.object(forKey: "llmProvider_gemini_modelID"))
        XCTAssertNil(defaults.object(forKey: "voiceProviderID"))
        XCTAssertNil(defaults.object(forKey: "voiceOpenAIModelID"))
    }

    func testVoiceSettingsCustomHotKeyRoundTrips() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        var settings = LLMSettings.empty()
        settings.voice.hotKey = AppHotKey(
            carbonKeyCode: Key.space.carbonKeyCode,
            carbonModifiers: NSEvent.ModifierFlags([.control, .shift]).carbonFlags
        )

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.voice.hotKey, settings.voice.hotKey)
        XCTAssertEqual(loaded.voice.hotKey.displayValue, "⌃⇧␣")
    }

    func testVoiceSettingsMouseButtonHotKeyRoundTrips() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        var settings = LLMSettings.empty()
        settings.voice.hotKey = AppHotKey(mouseButtonNumber: 4)

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.voice.hotKey, settings.voice.hotKey)
        XCTAssertEqual(loaded.voice.hotKey.readableDisplayValue, "Mouse Button 4")
    }

    func testClipboardHistoryDefaultMaxStoredRecordsIs1000() {
        XCTAssertEqual(ClipboardHistorySettings.default.maxStoredRecords, 1_000)
    }

    func testClipboardHistoryMaxStoredRecordsIsCappedAt10000() {
        let settings = ClipboardHistorySettings(maxStoredRecords: 20_000)

        XCTAssertEqual(settings.maxStoredRecords, ClipboardHistorySettings.maxStoredRecordsLimit)
    }
}

private final class InMemoryLLMSecretsStore: LLMSecretsStoring {
    private var values: [LLMProviderID: String]

    init(values: [LLMProviderID: String] = [:]) {
        self.values = values
    }

    func apiKey(for providerID: LLMProviderID) -> String {
        values[providerID] ?? ""
    }

    func setAPIKey(_ apiKey: String, for providerID: LLMProviderID) {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            values.removeValue(forKey: providerID)
        } else {
            values[providerID] = normalized
        }
    }
}
