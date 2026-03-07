import Foundation
import XCTest
@testable import Steward

final class LLMSettingsMigrationTests: XCTestCase {
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

        store.saveSettings(settings)
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.profile(for: .openAI).apiKey, "openai-key")
        XCTAssertEqual(loaded.profile(for: .gemini).apiKey, "gemini-key")
        XCTAssertEqual(loaded.grammarProviderID, .gemini)
        XCTAssertEqual(loaded.screenshotProviderID, .openAI)
    }

    func testMigrationLegacyMethodIsNoOp() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("legacy-openai-key", forKey: "openAIApiKey")
        defaults.set("legacy-gemini-key", forKey: "geminiAPIKey")

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        store.migrateLegacySettingsIfNeeded()
        let loaded = store.loadSettings()

        XCTAssertEqual(loaded.profile(for: .openAI).apiKey, "")
        XCTAssertEqual(loaded.profile(for: .gemini).apiKey, "")
    }

    func testCustomInstructionsRoundTrip() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())

        store.setCustomGrammarInstructions("Rule 1\nRule 2")
        store.setCustomScreenshotInstructions("Keep bullet lists")

        XCTAssertEqual(store.customGrammarInstructions(), "Rule 1\nRule 2")
        XCTAssertEqual(store.customScreenshotInstructions(), "Keep bullet lists")
    }

    func testClipboardHistorySettingsDefaultToDisabled() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())

        XCTAssertEqual(store.clipboardHistorySettings(), .default)
    }

    func testClipboardHistorySettingsRoundTrip() {
        let suiteName = "LLMSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults, secretsStore: InMemoryLLMSecretsStore())
        let settings = ClipboardHistorySettings(isEnabled: true, maxStoredRecords: 250)

        store.setClipboardHistorySettings(settings)

        XCTAssertEqual(store.clipboardHistorySettings(), settings)
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
