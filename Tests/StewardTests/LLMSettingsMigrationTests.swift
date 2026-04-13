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
        settings.refine = RefineSettings(
            selectedModel: LLMModelSelection(
                providerID: .openAI,
                modelID: LLMModelCatalog.defaultModelID(for: .openAI)
            ),
            customInstructions: "Rule 1\nRule 2"
        )
        settings.screenText = ScreenTextSettings(
            selectedModel: LLMModelSelection(
                providerID: .gemini,
                modelID: LLMModelCatalog.defaultModelID(for: .gemini)
            ),
            customInstructions: "Keep bullet lists"
        )
        settings.voice = VoiceSettings(
            selectedModel: LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe"),
            customInstructions: "Keep speaker intent",
            hotKey: AppHotKey(
                carbonKeyCode: Key.v.carbonKeyCode,
                carbonModifiers: NSEvent.ModifierFlags([.command, .option]).carbonFlags
            ),
            preferredRecognitionLanguages: [.english, .spanish, .english, .french],
            translateToLanguageEnabled: true,
            translationTargetLanguage: .german
        )
        settings.clipboardHistory = ClipboardHistorySettings(isEnabled: true, maxStoredRecords: 250)

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.providerSettings(for: .openAI).apiKey, "openai-key")
        XCTAssertEqual(loaded.providerSettings(for: .gemini).apiKey, "gemini-key")
        XCTAssertEqual(loaded.refine, settings.refine)
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

        XCTAssertEqual(settings.refine.customInstructions, "")
        XCTAssertEqual(settings.screenText.customInstructions, "")
        XCTAssertNil(settings.refine.selectedModel)
        XCTAssertNil(settings.screenText.selectedModel)
        XCTAssertNil(settings.voice.selectedModel)
        XCTAssertEqual(settings.voice.hotKey, .defaultVoiceDictation)
        XCTAssertEqual(settings.voice.hotKey.displayValue, "⌃⇧␣")
        XCTAssertEqual(settings.voice.preferredRecognitionLanguages, [])
        XCTAssertFalse(settings.voice.translateToLanguageEnabled)
        XCTAssertNil(settings.voice.translationTargetLanguage)
        XCTAssertEqual(settings.clipboardHistory, .default)
    }

    func testSaveSettingsUsesRefineKeysOnly() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        var settings = LLMSettings.empty()
        settings.providerSettings[.openAI] = LLMProviderSettings(apiKey: "openai-key")
        settings.refine = RefineSettings(
            selectedModel: LLMModelSelection(providerID: .openAI, modelID: "gpt-5.4"),
            customInstructions: "Keep meaning"
        )

        store.saveSettings(settings)

        XCTAssertEqual(defaults.string(forKey: "refineSelectedProviderID"), LLMProviderID.openAI.rawValue)
        XCTAssertEqual(defaults.string(forKey: "refineSelectedModelID"), "gpt-5.4")
        XCTAssertEqual(defaults.string(forKey: "customRefineInstructions"), "Keep meaning")
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

    func testVoiceSettingsPreferredLanguagesRoundTripWithDedupingAndCap() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        var settings = LLMSettings.empty()
        settings.voice.preferredRecognitionLanguages = [
            .english, .spanish, .english, .french, .german, .italian, .japanese
        ]

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(
            loaded.voice.preferredRecognitionLanguages,
            [.english, .spanish, .french, .german, .italian]
        )
    }

    func testVoiceSettingsTranslateModeRoundTrips() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        var settings = LLMSettings.empty()
        settings.voice.translateToLanguageEnabled = true
        settings.voice.translationTargetLanguage = .japanese

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertTrue(loaded.voice.translateToLanguageEnabled)
        XCTAssertEqual(loaded.voice.translationTargetLanguage, .japanese)
    }

    func testSaveSettingsRestoresCanonicalDefaultModeName() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        var settings = LLMSettings.empty()
        settings.voice.modes = [
            DictateMode(
                id: DictateMode.defaultModeID,
                name: "Renamed",
                customInstructions: "Keep speaker intent",
                isDefault: true
            )
        ]

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.voice.modes.first?.name, "Default")
        XCTAssertEqual(loaded.voice.modes.first?.customInstructions, "Keep speaker intent")
    }

    func testLegacyVoiceHotKeyKeysResetToNewSingleHotKeyDefault() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(AppHotKey.TriggerKind.keyboard.rawValue, forKey: "voiceHotKeyTriggerKind")
        defaults.set(Int(Key.v.carbonKeyCode), forKey: "voiceHotKeyCode")
        defaults.set(Int(NSEvent.ModifierFlags([.command, .option]).carbonFlags), forKey: "voiceHotKeyModifiers")
        defaults.set(0, forKey: "voiceHotKeyMouseButtonNumber")

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.voice.hotKey, .defaultVoiceDictation)
    }

    func testSaveSettingsStoresCanonicalDictateKeysAndClearsLegacyKeys() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("stale", forKey: "voiceHotKeyTriggerKind")
        defaults.set(99, forKey: "voiceHotKeyCode")
        defaults.set(99, forKey: "voiceHotKeyModifiers")
        defaults.set(4, forKey: "voiceHotKeyMouseButtonNumber")
        defaults.set("stale", forKey: "voiceRegularHotKeyTriggerKind")
        defaults.set(99, forKey: "voiceRegularHotKeyCode")
        defaults.set(99, forKey: "voiceRegularHotKeyModifiers")
        defaults.set(4, forKey: "voiceRegularHotKeyMouseButtonNumber")

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        var settings = LLMSettings.empty()
        settings.voice.hotKey = AppHotKey(
            carbonKeyCode: Key.v.carbonKeyCode,
            carbonModifiers: NSEvent.ModifierFlags([.command, .option]).carbonFlags
        )

        store.saveSettings(settings)

        XCTAssertEqual(defaults.string(forKey: "voiceDictateHotKeyTriggerKind"), AppHotKey.TriggerKind.keyboard.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "voiceDictateHotKeyCode"), Int(Key.v.carbonKeyCode))
        XCTAssertEqual(
            defaults.integer(forKey: "voiceDictateHotKeyModifiers"),
            Int(NSEvent.ModifierFlags([.command, .option]).carbonFlags)
        )
        XCTAssertEqual(defaults.integer(forKey: "voiceDictateHotKeyMouseButtonNumber"), 0)
        XCTAssertNil(defaults.object(forKey: "voiceHotKeyTriggerKind"))
        XCTAssertNil(defaults.object(forKey: "voiceHotKeyCode"))
        XCTAssertNil(defaults.object(forKey: "voiceHotKeyModifiers"))
        XCTAssertNil(defaults.object(forKey: "voiceHotKeyMouseButtonNumber"))
        XCTAssertNil(defaults.object(forKey: "voiceRegularHotKeyTriggerKind"))
        XCTAssertNil(defaults.object(forKey: "voiceRegularHotKeyCode"))
        XCTAssertNil(defaults.object(forKey: "voiceRegularHotKeyModifiers"))
        XCTAssertNil(defaults.object(forKey: "voiceRegularHotKeyMouseButtonNumber"))
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
