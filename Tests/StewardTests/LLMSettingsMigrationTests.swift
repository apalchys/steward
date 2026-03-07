import Foundation
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
        settings.grammarProviderID = .gemini
        settings.screenshotProviderID = .openAI
        settings.grammarCustomInstructions = "Rule 1\nRule 2"
        settings.screenshotCustomInstructions = "Keep bullet lists"
        settings.clipboardHistory = ClipboardHistorySettings(isEnabled: true, maxStoredRecords: 250)

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.profile(for: .openAI).apiKey, "openai-key")
        XCTAssertEqual(loaded.profile(for: .gemini).apiKey, "gemini-key")
        XCTAssertEqual(loaded.grammarProviderID, .openAI)
        XCTAssertEqual(loaded.screenshotProviderID, .gemini)
        XCTAssertEqual(loaded.grammarCustomInstructions, "Rule 1\nRule 2")
        XCTAssertEqual(loaded.screenshotCustomInstructions, "Keep bullet lists")
        XCTAssertEqual(loaded.clipboardHistory, ClipboardHistorySettings(isEnabled: true, maxStoredRecords: 250))
    }

    func testLoadSettingsDefaultsCustomInstructionsAndClipboardHistory() {
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
        XCTAssertEqual(settings.clipboardHistory, .default)
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
