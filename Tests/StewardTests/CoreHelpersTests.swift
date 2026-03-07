import XCTest
@testable import StewardCore

final class CoreHelpersTests: XCTestCase {
    func testBuildGrammarPromptReturnsBasePromptWhenRulesAreEmpty() {
        let defaultPrompt = buildGrammarPrompt(customRules: "")
        let whitespacePrompt = buildGrammarPrompt(customRules: "  \n\t")

        XCTAssertEqual(whitespacePrompt, defaultPrompt)
    }

    func testBuildGrammarPromptAppendsCustomRules() {
        let customRules = "Prefer short sentences."
        let prompt = buildGrammarPrompt(customRules: customRules)

        XCTAssertTrue(prompt.contains("Additional rules to follow:"))
        XCTAssertTrue(prompt.hasSuffix(customRules))
    }

    func testPreferenceValueReturnsDefaultWhenMissingOrWhitespace() {
        let key = "CoreHelpersTests.preference.\(UUID().uuidString)"
        let defaultValue = "default-model"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        XCTAssertEqual(preferenceValue(forKey: key, defaultValue: defaultValue), defaultValue)

        UserDefaults.standard.set("   ", forKey: key)
        XCTAssertEqual(preferenceValue(forKey: key, defaultValue: defaultValue), defaultValue)
    }

    func testPreferenceValueReturnsTrimmedStoredValue() {
        let key = "CoreHelpersTests.preference.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set("  gpt-5.4  ", forKey: key)
        XCTAssertEqual(preferenceValue(forKey: key, defaultValue: "fallback"), "gpt-5.4")
    }

    func testSavePreferenceValueStoresDefaultWhenInputIsEmpty() {
        let key = "CoreHelpersTests.save.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        savePreferenceValue("   ", forKey: key, defaultValue: "fallback")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "fallback")
    }

    func testSavePreferenceValueStoresTrimmedInput() {
        let key = "CoreHelpersTests.save.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        savePreferenceValue("  custom-model  ", forKey: key, defaultValue: "fallback")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "custom-model")
    }
}
