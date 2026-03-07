import Foundation
import XCTest
@testable import Steward

final class GrammarCoordinatorTests: XCTestCase {
    func testHandleHotKeyPressSendsRequestThroughRouterAndReplacesTextOnSuccess() {
        let router = FakeRouter(result: .success(.text("corrected")))
        let textInteraction = FakeTextInteraction(selectedText: "bad")
        let settingsStore = CoordinatorSettingsStore(
            settings: {
                var settings = LLMSettings.empty()
                settings.grammarProviderOverrideID = .openAICompatible
                settings.providerProfiles[.openAICompatible] = LLMProviderProfile(
                    apiKey: "key",
                    modelID: "model",
                    baseURL: "https://example.com"
                )
                return settings
            }(),
            customRules: "Use concise language"
        )

        let coordinator = GrammarCoordinator(router: router, textInteraction: textInteraction, settingsStore: settingsStore)

        let result: Result<Void, Error> = waitForValue { completion in
            coordinator.handleHotKeyPress(completion: completion)
        }

        switch result {
        case .success:
            XCTAssertEqual(textInteraction.replacedText, "corrected")
            guard let request = router.lastRequest else {
                XCTFail("Expected request to be routed")
                return
            }

            guard case let .grammarCorrection(text, customRules) = request.task else {
                XCTFail("Expected grammar task")
                return
            }

            XCTAssertEqual(text, "bad")
            XCTAssertEqual(customRules, "Use concise language")
            XCTAssertEqual(request.featureOverrideProviderID, .openAICompatible)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testHandleHotKeyPressFailsWhenNoSelectedText() {
        let router = FakeRouter(result: .success(.text("ignored")))
        let textInteraction = FakeTextInteraction(selectedText: nil)
        let settingsStore = CoordinatorSettingsStore(settings: .empty(), customRules: "")

        let coordinator = GrammarCoordinator(router: router, textInteraction: textInteraction, settingsStore: settingsStore)

        let result: Result<Void, Error> = waitForValue { completion in
            coordinator.handleHotKeyPress(completion: completion)
        }

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            guard case GrammarCoordinatorError.noSelectedText = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertNil(router.lastRequest)
            XCTAssertNil(textInteraction.replacedText)
        }
    }

    func testHandleHotKeyPressPropagatesRouterError() {
        enum TestError: Error {
            case failed
        }

        let router = FakeRouter(result: .failure(TestError.failed))
        let textInteraction = FakeTextInteraction(selectedText: "bad")
        let settingsStore = CoordinatorSettingsStore(settings: .empty(), customRules: "")

        let coordinator = GrammarCoordinator(router: router, textInteraction: textInteraction, settingsStore: settingsStore)

        let result: Result<Void, Error> = waitForValue { completion in
            coordinator.handleHotKeyPress(completion: completion)
        }

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            guard case TestError.failed = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertNil(textInteraction.replacedText)
        }
    }
}

private final class FakeRouter: LLMRouting {
    var supportedProviderIDs: [LLMProviderID] = [.openAI]
    var lastRequest: LLMRequest?
    var result: Result<LLMResult, Error>

    init(result: Result<LLMResult, Error>) {
        self.result = result
    }

    func perform(_ request: LLMRequest, completion: @escaping (Result<LLMResult, Error>) -> Void) {
        lastRequest = request
        completion(result)
    }

    func resolvedProviderID(for capability: LLMCapability, featureOverrideProviderID: LLMProviderID?) -> LLMProviderID? {
        featureOverrideProviderID ?? .openAI
    }

    func checkAccess(
        for capability: LLMCapability,
        featureOverrideProviderID: LLMProviderID?,
        completion: @escaping (Result<LLMProviderHealth, Error>) -> Void
    ) {
        completion(.success(LLMProviderHealth(providerID: .openAI, hasAccess: true)))
    }
}

private final class FakeTextInteraction: TextInteractionPerforming {
    var selectedText: String?
    var replacedText: String?
    var copiedText: String?

    init(selectedText: String?) {
        self.selectedText = selectedText
    }

    func getSelectedText() -> String? {
        selectedText
    }

    func replaceSelectedText(with newText: String) {
        replacedText = newText
    }

    func copyTextToClipboard(_ text: String) {
        copiedText = text
    }
}

final class CoordinatorSettingsStore: LLMSettingsProviding {
    var settings: LLMSettings
    var customRulesValue: String

    init(settings: LLMSettings, customRules: String) {
        self.settings = settings
        self.customRulesValue = customRules
    }

    func loadSettings() -> LLMSettings { settings }

    func saveSettings(_ settings: LLMSettings) {
        self.settings = settings
    }

    func migrateLegacySettingsIfNeeded() {}

    func customGrammarRules() -> String { customRulesValue }

    func setCustomGrammarRules(_ value: String) {
        customRulesValue = value
    }
}
