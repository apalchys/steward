import AppKit
import Foundation
import HotKey
import XCTest
@testable import Steward

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

    func testSaveAndLoadRoundTripsNonSecretsAndValetSecrets() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let secretsStore = InMemoryLLMSecretsStore()
        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: secretsStore)

        var settings = LLMSettings.empty()
        settings.providerProfiles[.openAI] = LLMProviderProfile(
            apiKey: "openai-key",
            modelID: "gpt-5.4"
        )
        settings.providerProfiles[.gemini] = LLMProviderProfile(
            apiKey: "gemini-key",
            modelID: "gemini-3.1-flash-lite-preview"
        )
        settings.grammarCustomInstructions = "Rule 1\nRule 2"
        settings.screenshotCustomInstructions = "Keep bullet lists"
        settings.voice = VoiceSettings(
            providerID: .openAI,
            geminiModelID: "gemini-custom",
            openAIModelID: "gpt-4o-mini-transcribe-custom",
            customInstructions: "Keep speaker intent",
            hotKey: AppHotKey(
                carbonKeyCode: Key.v.carbonKeyCode,
                carbonModifiers: NSEvent.ModifierFlags([.command, .option]).carbonFlags
            )
        )
        settings.clipboardHistory = ClipboardHistorySettings(isEnabled: true, maxStoredRecords: 250)

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.profile(for: .openAI).apiKey, "openai-key")
        XCTAssertEqual(loaded.profile(for: .gemini).apiKey, "gemini-key")
        XCTAssertEqual(loaded.grammarCustomInstructions, "Rule 1\nRule 2")
        XCTAssertEqual(loaded.screenshotCustomInstructions, "Keep bullet lists")
        XCTAssertEqual(
            loaded.voice,
            VoiceSettings(
                providerID: .openAI,
                geminiModelID: "gemini-custom",
                openAIModelID: "gpt-4o-mini-transcribe-custom",
                customInstructions: "Keep speaker intent",
                hotKey: AppHotKey(
                    carbonKeyCode: Key.v.carbonKeyCode,
                    carbonModifiers: NSEvent.ModifierFlags([.command, .option]).carbonFlags
                )
            )
        )
        XCTAssertEqual(loaded.clipboardHistory, ClipboardHistorySettings(isEnabled: true, maxStoredRecords: 250))
    }

    func testLoadSettingsDefaultsCustomInstructionsVoiceSettingsAndClipboardHistory() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())

        let settings = store.loadSettings()

        XCTAssertEqual(settings.grammarCustomInstructions, "")
        XCTAssertEqual(settings.screenshotCustomInstructions, "")
        XCTAssertEqual(settings.voice, .default)
        XCTAssertEqual(settings.clipboardHistory, .default)
    }

    func testVoiceSettingsEmptyModelIDsSaveBackAsDefaults() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        var settings = LLMSettings.empty()
        settings.voice = VoiceSettings(
            providerID: .gemini,
            geminiModelID: "   ",
            openAIModelID: "",
            customInstructions: "",
            hotKey: .defaultVoiceDictation
        )

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.voice, .default)
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
    private var values: [LLMProviderID: String] = [:]

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
