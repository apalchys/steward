import Foundation
import XCTest
@testable import Steward

final class LLMSettingsMigrationTests: XCTestCase {
    func testMigrationMovesLegacyOpenAIAndGeminiSettings() {
        let suiteName = "LLMSettingsMigrationTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("legacy-openai-key", forKey: "openAIApiKey")
        defaults.set("gpt-5.4", forKey: "openAIModelID")
        defaults.set("legacy-gemini-key", forKey: "geminiAPIKey")
        defaults.set("gemini-3.1-flash-lite-preview", forKey: "geminiModelID")

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults)
        store.migrateLegacySettingsIfNeeded()

        let settings = store.loadSettings()
        XCTAssertEqual(settings.profile(for: .openAI).apiKey, "legacy-openai-key")
        XCTAssertEqual(settings.profile(for: .openAI).modelID, "gpt-5.4")
        XCTAssertEqual(settings.profile(for: .gemini).apiKey, "legacy-gemini-key")
        XCTAssertEqual(settings.profile(for: .gemini).modelID, "gemini-3.1-flash-lite-preview")
        XCTAssertEqual(settings.globalDefaultProviderID, .openAI)
        XCTAssertTrue(defaults.bool(forKey: "llmSettingsMigratedV1"))
    }

    func testMigrationIsIdempotentAndDoesNotOverrideExistingNewSettings() {
        let suiteName = "LLMSettingsMigrationTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsLLMSettingsStore(userDefaults: defaults)
        var settings = LLMSettings.empty()
        settings.providerProfiles[.openAI] = LLMProviderProfile(
            apiKey: "new-openai-key",
            modelID: "gpt-new",
            baseURL: ""
        )
        store.saveSettings(settings)

        defaults.set("legacy-openai-key", forKey: "openAIApiKey")
        defaults.set("legacy-model", forKey: "openAIModelID")

        store.migrateLegacySettingsIfNeeded()
        let migrated = store.loadSettings()

        XCTAssertEqual(migrated.profile(for: .openAI).apiKey, "new-openai-key")
        XCTAssertEqual(migrated.profile(for: .openAI).modelID, "gpt-new")

        store.migrateLegacySettingsIfNeeded()
        let secondPass = store.loadSettings()
        XCTAssertEqual(secondPass.profile(for: .openAI).apiKey, "new-openai-key")
        XCTAssertEqual(secondPass.profile(for: .openAI).modelID, "gpt-new")
    }
}
